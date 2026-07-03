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
