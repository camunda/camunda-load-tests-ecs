# Stable Module Agent Instructions

## Purpose

Shared, long-lived AWS infrastructure (VPC, ECR, security groups, VPN gateway) consumed by all benchmark and monitoring modules.

## Environments

| Env | VPC CIDR | State key | Prefix |
|-----|----------|-----------|--------|
| dev | `10.52.0.0/16` | `stable/dev/terraform.tfstate` | `camunda-dev` |
| prod | `10.50.0.0/16` | `stable/prod/terraform.tfstate` | `camunda` |

`10.51.0.0/16` is reserved for a future stage environment.

## Commands

Run `make` from the environment subdirectory:

```bash
cd aws/stable/dev   && make plan    # plan dev
cd aws/stable/dev   && make apply   # apply dev
cd aws/stable/prod  && make plan    # plan prod
cd aws/stable/prod  && make apply   # apply prod
```

### Capturing plan output

**Never** run `make plan` more than once to inspect its output. Capture it once with `tee` and then read or grep the file:

```bash
make plan 2>&1 | tee /tmp/tf-plan-dev.out   # run ONCE
grep -i "plan:" /tmp/tf-plan-dev.out         # summary
grep "error"    /tmp/tf-plan-dev.out         # errors
cat /tmp/tf-plan-dev.out                     # full output
```

Use a descriptive temp filename per environment (e.g. `/tmp/tf-plan-prod.out`) to avoid confusion.

## Constraints

- **Never** run `terraform apply` directly — always use `make` from the env folder.
- **Never** destroy stable without destroying all dependent benchmarks/load tests first.
- **CIDR coordination:** VPC CIDRs must match what infra-core expects in [`terraform/network/cidrs.tf`](https://github.com/camunda/infra-core/blob/stage/terraform/network/cidrs.tf). VPN and firewall rules are managed there.
- **CI coupling:** Changes to stable infrastructure (folder structure, variables, Makefile targets) likely require matching updates in `.github/workflows/setup-stable-infrastructure.yml`.
- Per-environment config lives in `{dev,prod}/terraform.tfvars`.
- Shared make targets live in `shared.mk`.
- `aws/.envrc` sets `AWS_PROFILE`, `AWS_REGION`, and `VAULT_ADDR` via `direnv`

## Network & VPN

VPN gateway, tunnels, security groups for cross-cloud monitoring, and route propagation are all managed by `camunda/infra-core` (`camunda-benchmark/terraform/aws/`). This module only provisions the VPC — infra-core looks it up by CIDR and attaches the VPN resources.
