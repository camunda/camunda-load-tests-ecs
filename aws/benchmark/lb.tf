resource "aws_lb" "main" {
  name               = "${var.prefix}-alb-webui"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_camunda_ports"],
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_80_443"],
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_9600"]
  ]
  subnets = data.terraform_remote_state.stable.outputs.vpc_public_subnets
}

# ALB Listener for WebApp HTTP traffic (port 80)
# Uses fixed-response as default; the orchestration-cluster module adds path-based rules
resource "aws_lb_listener" "http_webapp" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = ""
      status_code  = "200"
    }
  }
}

# ALB Listener for management/metrics port (port 9600)
resource "aws_lb_listener" "http_management" {
  load_balancer_arn = aws_lb.main.arn
  port              = 9600
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = ""
      status_code  = "200"
    }
  }
}

resource "aws_lb" "grpc" {
  name               = "${var.prefix}-nlb-grpc"
  internal           = false
  load_balancer_type = "network"
  security_groups = [
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_camunda_ports"],
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_grpc"]
  ]

  subnets = data.terraform_remote_state.stable.outputs.vpc_public_subnets
}
