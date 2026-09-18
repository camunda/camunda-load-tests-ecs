# Owned by @camunda/infrastructure (see CODEOWNERS).
# Changes here affect metrics ingestion volume, which has reliability and finops implications.

# Dev environment
environment = "dev"
prefix      = "dev-monitoring"

# GCP CIDRs for Prometheus federation over Site-to-Site VPN
# Source: camunda/infra-core cidrs.tf → benchmark_gcp.dev
gcp_federation_cidrs = [
  "10.25.0.0/16",  # node network
  "10.125.0.0/16", # pod (container) CIDR
  "10.157.0.0/16", # additional pod CIDR (ext-subnet)
]

# Dual-region: allow this (primary) Prometheus to scrape the us-east-1
# secondary Prometheus's /federate over the cross-region VPC peering
# connection. CIDR = aws/stable us-east-1 VPC.
federation_target_cidrs = ["10.60.0.0/16"]

# Dual-region: federate the us-east-1 secondary Prometheus via its internal
# NLB (see aws/monitoring/us-east-1/terraform.tfvars: expose_via_internal_nlb).
federation_peer_monitoring_state_key = "monitoring/monitoring-us-east-1.tfstate"
