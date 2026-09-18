################################
# VPC State Data Source       #
################################

data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "zeebe-terraform-states"
    key    = var.vpc_state_path
    region = "eu-west-1"
  }
}

# Convenience local — every downstream reference uses local.vpc.region_N_*
# rather than digging into data.terraform_remote_state.vpc.outputs each time.
locals {
  vpc = data.terraform_remote_state.vpc.outputs
}

# AZs derived from the (possibly customer-supplied) private subnets.
# Aurora needs them via primary_availability_zones; this works regardless
# of whether the VPC was created by us or supplied via BYO.

data "aws_subnet" "region_0_private" {
  count = length(local.vpc.region_0_private_subnet_ids)
  id    = local.vpc.region_0_private_subnet_ids[count.index]
}

data "aws_subnet" "region_1_private" {
  count    = length(local.vpc.region_1_private_subnet_ids)
  provider = aws.accepter
  id       = local.vpc.region_1_private_subnet_ids[count.index]
}

################################################################
# Stable Stack State (registry credentials, synced from Vault) #
################################################################

# region 0 (eu-west-1) stable stack
data "terraform_remote_state" "stable" {
  backend = "s3"

  config = {
    bucket = "zeebe-terraform-states"
    key    = "stable/${var.stable_environment}/terraform.tfstate"
    region = "eu-west-1"
  }
}

# region 1 (us-east-1) stable stack
data "terraform_remote_state" "stable_us_east_1" {
  backend = "s3"

  config = {
    bucket = "zeebe-terraform-states"
    key    = "stable/us-east-1/terraform.tfstate"
    region = "eu-west-1"
  }
}
