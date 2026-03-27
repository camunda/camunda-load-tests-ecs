# Load Tests on ECS

This repository contains the terraform for C8 Orchestration Cluster benchmark infrastructure on AWS ECS.

## Prerequisites

### AWS Access

This project uses the **Core Foundation Team - Playground** AWS account (`030846071718`).

1. **Add the AWS SSO profile** (one-time setup) — add to `~/.aws/config`:

   ```ini
   [profile playground]
   region = eu-west-1
   sso_session = okta
   sso_account_id = 030846071718
   sso_role_name = SystemAdministrator
   ```

2. **Login** before running any Terraform commands:

   ```bash
   aws sso login --profile playground
   ```

### direnv

A `.envrc` in `aws/` automatically sets `AWS_PROFILE=playground`, `AWS_REGION=eu-west-1`, and `VAULT_ADDR` via [direnv](https://direnv.net/). On first use:

```bash
cd aws/
direnv allow
```

After that, any `make` command under `aws/` will use the correct profile and Vault address automatically.

### Vault

Registry credentials and other secrets are read from [HashiCorp Vault](https://vault.int.camunda.com/) at plan/apply time. The `make` targets automatically check for a valid Vault token before running Terraform — if no valid token exists, it will trigger an OIDC login via your browser. No manual login needed.

- **CI:** Authentication happens via AppRole through the `hashicorp/vault-action` GitHub Action.

### Tools

- Terraform >= 1.7.0 (or OpenTofu)
- AWS CLI v2 with SSO support
- Vault CLI
- [direnv](https://direnv.net/docs/installation.html)

> [!IMPORTANT]
> Never pass secret values as Terraform variables or in tfvars files. Let Terraform read secrets from Vault at plan/apply time (see `aws/stable/registry-auth.tf` for the pattern).

## Structure

### aws/stable

Shared, long-lived infrastructure (VPC, ECR, security groups, VPN gateway). Supports **dev** and **prod** environments with separate VPCs and state files. See [aws/stable/README.md](aws/stable/README.md) for details and networking coordination with the Infra team.

Each environment has its own subfolder with a `Makefile` and `terraform.tfvars`:

```bash
cd aws/stable/dev  && make plan     # plan dev
cd aws/stable/dev  && make apply    # apply dev
cd aws/stable/prod && make plan     # plan prod
cd aws/stable/prod && make apply    # apply prod
```

| Env | VPC CIDR | State key |
|-----|----------|-----------|  
| dev | `10.52.0.0/16` | `stable/dev/terraform.tfstate` |
| prod | `10.50.0.0/16` | `stable/prod/terraform.tfstate` |

Per-environment config is in `aws/stable/{dev,prod}/terraform.tfvars`. Shared make targets are in `aws/stable/shared.mk`.

### aws/benchmark

Contains ephemeral resources that the team can control and destroy without impacting the benchmarking project connection.

#### Running a benchmark

Run from the environment subdirectory (`dev` or `prod`).

**Using a numeric identifier** (existing convention):

```bash
cd aws/benchmark/dev
make deploy BENCHMARK_NUMBER=1 CAMUNDA_IMAGE=camunda/camunda:SNAPSHOT
```

```bash
cd aws/load_test/dev
make deploy BENCHMARK_NUMBER=1
```

**Using a custom name** (e.g., for weekly benchmarks):

```bash
cd aws/benchmark/dev
make deploy BENCHMARK_NAME=weekly-2026-03-17 CAMUNDA_IMAGE=camunda/camunda:SNAPSHOT
```

```bash
cd aws/load_test/dev
make deploy BENCHMARK_NAME=weekly-2026-03-17
```

When `BENCHMARK_NAME` is set it overrides `BENCHMARK_NUMBER`. The resulting prefix and state key are derived from the name (e.g., `PREFIX=dev-weekly-2026-03-17`, `BACKEND_KEY=dev/benchmarks/weekly-2026-03-17.tfstate`). In prod the `dev-` prefix is omitted.

> [!NOTE]
> AWS target group names are limited to 32 characters. The longest derived name is `<PREFIX>-oc-tg-26500` (12-char suffix), so `PREFIX` must be at most 20 characters. The Makefile validates this automatically before `plan`/`apply`.

Alternatively, use the **Deploy/Destroy ECS Benchmark and Load Test** GitHub Action, which supports `environment`, `benchmark_number`, and `benchmark_name` inputs.

#### Automated weekly benchmarks

A scheduled workflow (`ecs-benchmark-weekly.yml`) runs every Monday at 06:00 UTC. It:
1. Computes a date-based name (e.g., `weekly-2026-03-17`)
2. Pins the `SNAPSHOT` images to their current `@sha256:` digests
3. Destroys the previous week's benchmark
4. Deploys the current week's benchmark with the pinned images

It can also be triggered manually via `workflow_dispatch`.

#### Monitoring / Prometheus discovery

Prometheus discovers benchmark targets **dynamically** via a Cloud Map discovery sidecar — no hardcoded DNS records in the monitoring stack. When a benchmark is deployed or destroyed, Prometheus picks up the change automatically within ~30 seconds.

### Troubleshooting

#### Exec into a container/task
```
# Find the service name of the benchmark cluster
aws ecs list-services --cluster camunda-cluster

# Allow executing commands. This redeploys the service that can take a while.
aws ecs update-service \
  --cluster camunda-cluster \
  --service benchmark1-oc-orchestration-cluster \
  --enable-execute-command \
  --force-new-deployment

# Find a task by listing task for the benchmark cluster.
aws ecs list-tasks --cluster camunda-cluster --service-name benchmark1-oc-orchestration-cluster

# Exec into one of the task (equivalent to kubectl exec)
aws ecs execute-command \
        --cluster camunda-cluster \
        --task $TASK_ARN \
        --container orchestration-cluster \
        --interactive \
        --command "/bin/bash"
```

#### Inspecting Lease objects in S3

List buckets
```
aws s3api list-buckets
```

List objects
```
aws s3api list-objects-v2 --bucket "benchmark3-oc-bucket"
```

Get contents of an object in to a local file `2.json`

```
aws s3api get-object --bucket "benchmark3-oc-bucket" --key="2.json" 2.json
```

Get only the header of an object
```
aws s3api head-object --bucket "benchmark3-oc-bucket" --key "2.json"
```

To overwrite the lease object, make sure to copy the metadata from the original object. The properties in the metadata and the json object must match. 
```
aws s3api put-object \
  --bucket "benchmark3-oc-bucket" \
  --key "2.json" \
  --body 2.json \
  --metadata "version=2,acquirable=true,taskId=xyz"
```

#### Destroy stuck on failing ECS service (bad image / pull errors)

If a benchmark is deployed with a non-existent image, ECS retries indefinitely (circuit breaker is disabled). This blocks `terraform destroy` because Terraform waits for the service to stabilize before deleting it.

**Symptoms:**
- `terraform destroy` hangs or times out on `aws_ecs_service`
- ECS events show `CannotPullContainerError` in a loop
- Service has `runningCount: 0` but `desiredCount: N`

**Fix — scale to zero first:**
```bash
# Check the service status
aws ecs describe-services --cluster camunda-cluster \
  --services benchmark2-oc-orchestration-cluster \
  --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Events:events[0:2]}'

# Scale to 0 to stop the retry loop
aws ecs update-service --cluster camunda-cluster \
  --service benchmark2-oc-orchestration-cluster \
  --desired-count 0

# Now terraform destroy will work
cd aws/benchmark/prod
make destroy-with-bucket BENCHMARK_NUMBER=2
# Or, if using a named benchmark:
# make destroy-with-bucket BENCHMARK_NAME=weekly-2026-03-17
```

Alternatively, use the `force-stop` make target which does this automatically:
```bash
cd aws/benchmark/prod
make force-stop BENCHMARK_NUMBER=2
# then:
make destroy-with-bucket BENCHMARK_NUMBER=2
```

> **Note:** The CI workflow (`Deploy ECS Benchmark and Load Test`) already runs `force-stop` before every destroy, so this deadlock cannot happen in automated deployments.
