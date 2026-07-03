# Security group to allow GKE Prometheus federation from GCP over Site-to-Site VPN.
# GKE pods scrape the AWS ECS Prometheus on port 9001; their source IPs come from
# GCP node/pod CIDRs which are outside the AWS VPC CIDR range.
# Source of truth for the CIDRs: camunda/infra-core terraform/network/cidrs.tf (benchmark_gcp).

resource "aws_security_group" "allow_gcp_prometheus_federation" {
  count = length(var.gcp_federation_cidrs) > 0 ? 1 : 0

  name        = "${var.prefix}-allow-gcp-prometheus-federation"
  description = "Allow inbound Prometheus federation from GCP benchmark CIDRs over VPN"
  vpc_id      = data.terraform_remote_state.stable.outputs.vpc_id

  ingress {
    from_port   = local.prometheus_port
    to_port     = local.prometheus_port
    protocol    = "TCP"
    cidr_blocks = var.gcp_federation_cidrs
    description = "Allow GKE Prometheus federation from GCP (infra-core benchmark_gcp CIDRs)"
  }

  tags = {
    Name = "${var.prefix}-allow-gcp-prometheus-federation"
  }
}

# Cross-region dual-region Prometheus federation, over VPC peering.
#
# federation_source_cidrs: CIDRs allowed to scrape THIS Prometheus's /federate
# (ingress) — set on the region_1 (secondary) monitoring instance to the
# primary's VPC CIDR, so the primary can pull region_1's metrics.
#
# federation_target_cidrs: CIDRs THIS Prometheus needs to reach on :9001 to
# scrape a remote /federate (egress) — set on the primary monitoring
# instance to region_1's VPC CIDR.
resource "aws_security_group" "allow_dual_region_federation" {
  count = length(var.federation_source_cidrs) > 0 || length(var.federation_target_cidrs) > 0 ? 1 : 0

  name        = "${var.prefix}-allow-dual-region-federation"
  description = "Allow cross-region Prometheus federation over VPC peering"
  vpc_id      = data.terraform_remote_state.stable.outputs.vpc_id

  dynamic "ingress" {
    for_each = length(var.federation_source_cidrs) > 0 ? [1] : []
    content {
      from_port   = local.prometheus_port
      to_port     = local.prometheus_port
      protocol    = "TCP"
      cidr_blocks = var.federation_source_cidrs
      description = "Allow the paired region Prometheus to scrape /federate"
    }
  }

  dynamic "egress" {
    for_each = length(var.federation_target_cidrs) > 0 ? [1] : []
    content {
      from_port   = local.prometheus_port
      to_port     = local.prometheus_port
      protocol    = "TCP"
      cidr_blocks = var.federation_target_cidrs
      description = "Allow scraping the paired region Prometheus /federate"
    }
  }

  tags = {
    Name = "${var.prefix}-allow-dual-region-federation"
  }
}
