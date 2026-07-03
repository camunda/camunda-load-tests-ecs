# Dual-region secondary (region_1) Prometheus — discovers us-east-1 brokers
# locally via Cloud Map, and is federated by the primary (eu-west-1)
# Prometheus over VPC peering.
#
# environment must match the env the dual-region cluster_name is prefixed
# with (see aws/dual-region/{vpc,infra}/dev — cluster_name = "dev-camunda-dr"),
# since the discovery sidecar filters Cloud Map namespaces by dev-*/non-dev-*.
# Only one dual-region test (dev or prod) is expected to run at a time.
environment      = "dev"
prefix           = "monitoring-us-east-1"
region           = "us-east-1"
stable_state_key = "stable/us-east-1/terraform.tfstate"

# Allow the primary (eu-west-1) Prometheus to scrape this instance's /federate
# over the cross-region VPC peering connection. CIDR = aws/stable dev VPC.
federation_source_cidrs = ["10.52.0.0/16"]

# Expose Prometheus via an internal NLB so the primary can reach it
# cross-region (Cloud Map DNS doesn't resolve across VPC peering).
expose_via_internal_nlb = true
