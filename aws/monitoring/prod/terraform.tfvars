# Owned by @camunda/infrastructure (see CODEOWNERS).
# Changes here affect metrics ingestion volume, which has reliability and finops implications.

# Prod environment
environment = "prod"
prefix      = "monitoring"

# GCP CIDRs for Prometheus federation over Site-to-Site VPN
# Source: camunda/infra-core cidrs.tf → benchmark_gcp.prod
gcp_federation_cidrs = [
  "10.5.0.0/16",   # node network
  "10.105.0.0/16", # pod (container) CIDR
  "10.152.0.0/14", # additional pod CIDR (ext-subnet)
]
