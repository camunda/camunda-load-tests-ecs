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
