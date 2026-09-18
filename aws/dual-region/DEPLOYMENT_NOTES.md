# Dual-Region Load Test — Deployment Notes

Dual-region Camunda cluster (4 brokers, 2 per region, replication factor 2, 4
partitions) spanning **eu-west-1** (primary / region_0) and **us-east-1**
(secondary / region_1, simulating a far region). Built from the
[camunda-deployment-references ecs-dual-region-fargate](https://github.com/camunda/camunda-deployment-references/tree/main/aws/containers/ecs-dual-region-fargate)
reference architecture.

## Architecture

- Three chained Terraform states: `vpc` → `infra` → `app`. Each manages both
  regions in a single apply via two AWS provider aliases.
- Networking: **VPC peering** (`networking_mode = "vpc_peering"`) between the
  two stable VPCs. No Transit Gateway (TGW module is skipped when peering mode
  is selected).
- **BYO VPC** (`byo_vpc = true`): reuses the existing `aws/stable` VPCs instead
  of creating new ones.
  - region_0 ← `aws/stable/dev` (eu-west-1, `10.52.0.0/16`)
  - region_1 ← `aws/stable/us-east-1` (us-east-1, `10.60.0.0/16`)
  - BYO wiring reads both stable states via `terraform_remote_state` data
    sources (`vpc/data.tf`), so it can never drift from the actual stable
    deployments.
- `cluster_name = "dev-camunda-dr"` — the `dev-` prefix is required: the
  monitoring discovery sidecar filters Cloud Map namespaces by `dev-*` vs
  non-`dev-*`, so `aws/monitoring/us-east-1` is also pinned to
  `environment = "dev"` to match.

## aws/stable/us-east-1

Single dedicated instance (no dev/prod split) that exists solely to give the
dual-region setup a second region's VPC/ECS cluster to BYO. Flat layout —
`Makefile` carries `ENV = us-east-1`, `BACKEND_KEY = stable/us-east-1/terraform.tfstate`
directly, no env subfolder.

## Deploy Order

Each must finish before the next:

```bash
cd aws/stable/dev        && make deploy   # if not already applied
cd aws/stable/us-east-1  && make deploy   # MUST run before dual-region/vpc
cd aws/dual-region/vpc/dev   && make deploy   # cross-region VPC peering
cd aws/dual-region/infra/dev && make deploy   # Aurora Global, ECS clusters, LBs (~15-20 min)
cd aws/dual-region/app/dev   && make deploy   # Camunda brokers (~15-20 min for first cross-region Raft quorum)
```

For a UI-triggered deployment, run the **Deploy Dual-Region Load Test** workflow
from GitHub Actions. It performs the same `vpc → infra → app → load_test`
sequence. Select `postgresql` or `mysql`, provide the REST endpoint (including
`http://`), and the workflow passes `DUAL_REGION=true`. The load test is forced
to prefer REST because basic authentication is not supported by the gRPC path.
The MySQL Camunda image is selected automatically when no image override is
provided.

> If `dual-region/vpc/dev` errors with `No stored state was found ... stable_region_1`,
> it means `aws/stable/us-east-1` was never applied — run it first.

## Monitoring

- Primary (`aws/monitoring/dev`, eu-west-1, prefix `dev-monitoring`) discovers
  region_0 brokers the normal way (same VPC, Cloud Map).
- Region_1 gets its own Prometheus (`aws/monitoring/us-east-1`) that discovers
  region_1 brokers locally.
- Primary **federates** region_1's Prometheus over VPC peering via an internal
  NLB — Cloud Map DNS doesn't resolve cross-region. Federation job is
  `federate-secondary` in the primary's scrape config.

Deploy the secondary Prometheus before (re-)applying the primary so the
federation target exists:

```bash
cd aws/monitoring/us-east-1 && make deploy
cd aws/monitoring/dev       && make deploy   # picks up the federation job
```

## Checking Prometheus / scraping

Prometheus is **internal-only** — no public LB on port 9001. The public ALB
(`<prefix>-al-webui`) only fronts the Grafana webui (3000/80/443).

- Prometheus port: **9001** (from `aws/stable` `ports.prometheus`).
- Private Cloud Map DNS: `prometheus.dev-monitoring.service.local:9001`
  (primary), reachable from inside the VPC / over VPN.
- Targets page: `http://prometheus.dev-monitoring.service.local:9001/targets`.
  - `job="core"` → region_0 brokers.
  - `job="federate-secondary"` → region_1 Prometheus `/federate` (target =
    us-east-1 internal NLB DNS).

Reach it via VPN, or ECS-exec into the task:

```bash
aws ecs execute-command --cluster <cluster> --task <task-arn> \
  --container prometheus --interactive --command "/bin/sh"
curl localhost:9001/targets
```

Get the (Grafana) ALB endpoint from the root state:

```bash
cd aws/monitoring/dev
terraform -chdir=.. output alb_endpoint
```

Note: the central Grafana federating eu-west-1 Prometheus uses the pre-existing
`gcp_federation_cidrs` SG rule (`security.tf`, `allow_gcp_prometheus_federation`),
untouched by the dual-region work.

## Load generation (primary region only)

No dedicated Terraform — reuse the single-region `aws/load_test` module. It reads
the `stable/dev` state, which is region_0's BYO VPC, and its `BENCHMARK_NAME`
override targets an arbitrary cluster:

Unlike the regular single-region benchmark (`CAMUNDA_SECURITY_AUTHENTICATION_UNPROTECTEDAPI=true`),
the dual-region cluster runs with **basic auth required** (`UNPROTECTEDAPI=false`), so the
load generator must authenticate. Pass the `admin` user credentials — the password lives
in the dual-region infra secret (a customer-managed KMS key encrypts it, so the load-test
execution role also needs `kms:Decrypt`):

```bash
cd aws/load_test/dev

SECRET_ARN=$(terraform -chdir=../../dual-region/infra output -raw admin_user_password_secret_region_0_arn)
KMS_ARN=$(aws secretsmanager describe-secret --secret-id "$SECRET_ARN" --query KmsKeyId --output text)

make deploy BENCHMARK_NAME=camunda-dr-r0 \
  CAMUNDA_AUTH_USERNAME=admin \
  CAMUNDA_AUTH_PASSWORD_SECRET_ARN="$SECRET_ARN" \
  CAMUNDA_AUTH_PASSWORD_KMS_KEY_ARN="$KMS_ARN"
```

When `CAMUNDA_AUTH_USERNAME` is empty (regular benchmarks against an unprotected API) the
load test injects no auth env/secret and needs no extra IAM — same behaviour as before.
The client config mirrors the dual-region connectors task (`CAMUNDA_CLIENT_MODE=self-managed`,
`CAMUNDA_CLIENT_AUTH_METHOD=basic`, `CAMUNDA_CLIENT_AUTH_USERNAME`, secret
`CAMUNDA_CLIENT_AUTH_PASSWORD`).

This gives (region_0 / eu-west-1 only):

- starter (1 task, 150 PI/s) + worker (3 tasks) pointed at
  `orchestration-cluster.dev-camunda-dr-r0-oc.service.local` (gRPC 26500,
  REST 8080) — the plain Cloud Map DNS name that resolves to the broker task IPs;
- `prefix = dev-camunda-dr-r0-lt`, state `dev/load_tests/camunda-dr-r0-lt.tfstate`;
- tasks run in the dual-region infra region_0 ECS cluster
  (`dev-camunda-dr-r0-cluster`) with the dual-region region_0 security groups —
  `DUAL_REGION=true` makes `aws/load_test/config.tf` read the cluster, subnets
  and SGs from the dual-region infra state instead of the `stable` state. The
  subnets are still the `stable/dev` VPC's private subnets (`byo_vpc = true`),
  so the tasks share the VPC with the region_0 brokers.

Why this works without SG changes: the region_0 broker SG
(`dual-region/infra/security.tf`, `camunda_ports_region_0`) allows all
`var.ports` from the whole region_0 VPC CIDR (`10.52.0.0/16`), so load tasks in
the shared VPC reach the brokers on 26500/8080 by CIDR, not by SG reference.

Only the primary region is loaded; region_1 stays a passive far-region replica.
Tear down with `make destroy BENCHMARK_NAME=camunda-dr-r0` from the same dir.

### Pointing the client at the region_0 load balancers (instead of Cloud Map)

By default the load client resolves `orchestration-cluster.<...>-oc.service.local`
(Cloud Map), which round-robins across **both** region_0 broker task IPs and pins
one gRPC connection to a single broker. If a task IP is stale/dead or its embedded
gateway is slow, gRPC hangs until the deadline (`DEADLINE_EXCEEDED`, with a large
`connecting_and_lb_delay` — note `call_credentials_delay` stays ~ms, so this is a
connectivity problem, not auth). The region_0 LBs front the same brokers with health
checks, so an unhealthy target is skipped.

`aws/load_test` exposes `GRPC_ADDRESS` / `REST_ADDRESS` overrides (empty = derive
from `CAMUNDA_HOST` Cloud Map DNS, unchanged for regular benchmarks). The dual-region
infra outputs the region_0 endpoints:

```bash
cd aws/load_test/dev
GRPC=$(terraform -chdir=../../dual-region/infra output -raw region_0_nlb_grpc_endpoint)
REST=$(terraform -chdir=../../dual-region/infra output -raw region_0_alb_endpoint)

make deploy BENCHMARK_NAME=camunda-dr-r0 \
  GRPC_ADDRESS="http://${GRPC}:26500" \
  REST_ADDRESS="http://${REST}:80" \
  CAMUNDA_AUTH_USERNAME=admin \
  CAMUNDA_AUTH_PASSWORD_SECRET_ARN="$SECRET_ARN" \
  CAMUNDA_AUTH_PASSWORD_KMS_KEY_ARN="$KMS_ARN"
```

- gRPC → external NLB `<prefix>-r0-nlb-grpc`, listener **26500**.
- REST → external ALB `<prefix>-r0-alb`, webapp listener on port **80** (forwards to
  broker 8080) — so REST uses `:80`, not `:8080`.

> **Caveat:** both LBs are internet-facing (`infra/lb.tf`, `internal = false`, public
> subnets). Load tasks in the private stable/dev subnet reach them via NAT, arriving
> with the NAT gateway's public IP. The broker SG `camunda_ports_region_0` only allows
> the region_0 VPC CIDR, so the NAT public IP must be covered by `remote_access_region_0`
> (external allowlist) or the LB connection is refused rather than balanced. Confirm the
> NAT egress IP is allowed before trusting a LB-vs-Cloud-Map comparison.

## Viewing metrics in Grafana (infra-core `benchmark` Grafana)

The dual-region metrics are **not** viewed in the AWS Grafana. They flow into the
`benchmark` Grafana stack in `camunda/infra-core`
(`camunda-benchmark/kustomize/.../monitoring/kube-prometheus-stack`). That
Grafana's in-cluster Prometheus federates the AWS ECS Prometheus via an
`aws-ecs-federation` job (`.../aws-federation-scrape-config.yml`) that scrapes
`/federate?match[]={job="core"}` and keeps source labels (`honor_labels: true`).

**Use the environment-matching dashboard.** The `dev-*` cluster (`dev-camunda-dr`)
is only scraped by `dev-monitoring`, and only the **dev** overlay federates
`prometheus.dev-monitoring.service.local`. The prod overlay federates
`prometheus.monitoring.service.local`, which by design discovers only non-`dev-*`
namespaces and therefore never sees `dev-camunda-dr`. So:

- dev cluster → `https://dev.dashboard.benchmark.camunda.cloud`
- prod cluster → `https://dashboard.benchmark.camunda.cloud`

Looking at the wrong environment's dashboard is the most likely reason "the target
is UP but Grafana shows nothing." Confirm which AWS Prometheus a benchmark
Prometheus federates via the `instance` label:
`scrape_samples_scraped{job="aws-ecs-federation"}` — `prometheus.dev-monitoring…`
vs `prometheus.monitoring…`.

### Label conventions for the ECS series

The discovery sidecar (`aws/monitoring/templates/discover-targets.sh`) labels each
target — these are NOT k8s-style, so dashboard variables must be set explicitly:

- `namespace = "ecs-<cloudmap-namespace-name>"`, e.g. `ecs-dev-camunda-dr-r0-oc`
- `cluster   = "ecs"` (hardcoded in the sidecar)
- `pod       = <ecs-task-id>`

Region_0 and region_1 both arrive as `job="core"` (region_1 keeps it through the
`federate-secondary` hop via `honor_labels: true`), distinguished only by the
`namespace` label (`…-r0-oc` vs `…-r1-oc`).

### Discovery requirements (for the sidecar to find a cluster)

The eu-west-1 `dev-monitoring` sidecar auto-discovers region_0 — no sidecar lives
in the dual-region app or the reference module. For it to match, the reference
`orchestration-cluster` module must expose, in eu-west-1 Cloud Map:

1. a private DNS namespace ending `-oc.service.local` and (for dev) starting
   `dev-` — here `dev-camunda-dr-r0-oc.service.local`;
2. a Cloud Map service named exactly `orchestration-cluster` in it;
3. broker tasks registered with `AWS_INSTANCE_IPV4`, metrics on port **9600**
   at `/actuator/prometheus`.

Debug path when region_0 is missing (all confirmable without VPN):

- sidecar logs / `benchmarks.json` in the `dev-monitoring` Prometheus task →
  should list `dev-camunda-dr-r0-oc` targets;
- ECS-exec into that task: `wget -qO- localhost:9001/api/v1/targets` → the
  `:9600` targets should be `health: "up"`;
- `wget -qO- 'localhost:9001/api/v1/query?query=count({namespace="ecs-dev-camunda-dr-r0-oc"})'`
  → non-zero confirms data is stored;
- `wget -qO- 'localhost:9001/federate?match[]={job="core"}' | grep -c ecs-dev-camunda-dr-r0-oc`
  → confirms `/federate` serves it to the benchmark Prometheus.

## Gotchas hit during first deploy

- **AWS resource name 32-char limit** (`lb.tf`): the `us-east-1` monitoring prefix
  `monitoring-us-east-1` is long, so NLB/target-group names use short suffixes
  (`-nlb-prom`, `-tg-prom`) to stay ≤ 32 chars.
- **SG description charset** (`security.tf`): AWS rejects apostrophes in
  `ingress/egress.description` (`^[0-9A-Za-z_ .:/()#,@\[\]+=&;{}!$*-]*$`) — keep the
  federation rule descriptions apostrophe-free.
- **Federation deploy order**: `aws/monitoring/dev` reads the secondary's remote
  state (`federation_peer_monitoring_state_key`); applying it before
  `aws/monitoring/us-east-1` fails with `No stored state was found`. Deploy the
  secondary first (see Monitoring section above).

## State-key migration (one-time, when adopting rotating names)

The deploy commands now key Terraform state on the run name:
`dual-region/<state>/<cluster_name>.tfstate` (e.g. `dev-camunda-dr.tfstate`),
where earlier the key was the fixed `dual-region/<state>/dev.tfstate`.

Before the first rotating deploy, retire the old stack so its resources don't
leak (it is an ephemeral benchmark cluster — destroying is expected):

Destroy the old-keyed stack in `app` → `infra` → `vpc` order, using the OLD
backend keys. Each command may only pass the variables that state actually
declares (see each module's `variables.tf`) — Terraform errors on undeclared
variables:

```bash
# app/ declares infra_state_path (no cluster_name).
terraform -chdir=aws/dual-region/app init -reconfigure \
  -backend-config="key=dual-region/app/dev.tfstate"
terraform -chdir=aws/dual-region/app destroy -auto-approve \
  -var-file=dev/terraform.tfvars \
  -var="infra_state_path=dual-region/infra/dev.tfstate"

# infra/ declares cluster_name and vpc_state_path (no infra_state_path).
terraform -chdir=aws/dual-region/infra init -reconfigure \
  -backend-config="key=dual-region/infra/dev.tfstate"
terraform -chdir=aws/dual-region/infra destroy -auto-approve \
  -var-file=dev/terraform.tfvars -var="cluster_name=dev-camunda-dr" \
  -var="vpc_state_path=dual-region/vpc/dev.tfstate"

# vpc/ declares cluster_name only (neither state path).
terraform -chdir=aws/dual-region/vpc init -reconfigure \
  -backend-config="key=dual-region/vpc/dev.tfstate"
terraform -chdir=aws/dual-region/vpc destroy -auto-approve \
  -var-file=dev/terraform.tfvars -var="cluster_name=dev-camunda-dr"
```

Afterwards all deploys go through the per-env Makefiles with `BENCHMARK_NAME`.
