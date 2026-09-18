resource "aws_lb" "monitoring" {
  name               = "${var.prefix}-al-webui"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_80_443"],
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_3000"],
  ]

  subnets = data.terraform_remote_state.stable.outputs.vpc_public_subnets
}

# Dual-region: gives this Prometheus a static DNS name reachable cross-region
# over VPC peering (NLB preserves client source IP, so the SG rule in
# security.tf keyed on federation_source_cidrs still applies).
resource "aws_lb" "prometheus_internal" {
  count              = var.expose_via_internal_nlb ? 1 : 0
  name               = "${var.prefix}-nlb-prom"
  internal           = true
  load_balancer_type = "network"
  subnets            = data.terraform_remote_state.stable.outputs.vpc_private_subnets
}

resource "aws_lb_target_group" "prometheus" {
  count       = var.expose_via_internal_nlb ? 1 : 0
  name        = "${var.prefix}-tg-prom"
  port        = local.prometheus_port
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = data.terraform_remote_state.stable.outputs.vpc_id
}

resource "aws_lb_listener" "prometheus" {
  count             = var.expose_via_internal_nlb ? 1 : 0
  load_balancer_arn = aws_lb.prometheus_internal[0].arn
  port              = local.prometheus_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus[0].arn
  }
}
