# Stable Infrastructure

Shared, long-lived AWS infrastructure (VPC, ECR, security groups, VPN gateway) used by all benchmark and monitoring modules. Supports `dev` and `prod` environments — run `make plan` / `make apply` from the respective subfolder.

## Networking

> [!IMPORTANT]
> Changes to VPC CIDRs or VPN configuration **must** be aligned with the Infrastructure team.

The leading CIDR configuration lives in [`camunda/infra-core` — `terraform/network/cidrs.tf`](https://github.com/camunda/infra-core/blob/stage/terraform/network/cidrs.tf). VPN gateway, tunnels, and cross-cloud monitoring firewall rules are managed by infra-core (`camunda-benchmark/terraform/aws/`) — this module only provides the VPC.

- **Questions or requests for Infra to make changes:** [#ask-infra](https://camunda.slack.com/archives/C5AHF1D8T)
- **PRs that need Infra review:** [#epo-reviews](https://camunda.slack.com/archives/C090HGYE5T2) (tag the Infra team)
