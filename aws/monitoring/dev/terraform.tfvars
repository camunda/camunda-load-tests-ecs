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
