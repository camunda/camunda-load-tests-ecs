################################
# Infra State Data Source     #
################################

data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = "zeebe-terraform-states"
    key    = var.infra_state_path
    region = "eu-west-1"
  }
}

# Convenience local to avoid repeating data.terraform_remote_state.infra.outputs everywhere
locals {
  infra = data.terraform_remote_state.infra.outputs
}

# Data sources needed by modules
data "aws_region" "region_0" {}

data "aws_region" "region_1" {
  provider = aws.accepter
}
