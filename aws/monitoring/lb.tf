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
