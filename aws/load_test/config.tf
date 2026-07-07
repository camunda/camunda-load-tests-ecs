terraform {

  required_version = ">= 1.7.0"
  backend "s3" {
    bucket = "zeebe-terraform-states"
    # To override this use -backend-config option with terraform init
    key    = "load_test1/load_test1.tfstate"
    region = "eu-west-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      managed_by = "Terraform"
      repository = "camunda/zeebe-terraform"
      folder     = "aws/load_test"
    }
  }
}

locals {
  stable_state_key = "stable/${var.environment}/terraform.tfstate"

  # When dual_region is set, deploy the load generators into the dual-region
  # region-0 VPC/cluster (so Cloud Map DNS resolves and no public LB hop is
  # needed). Otherwise use the single-region stable stack as-is.
  is_dual_region = var.dual_region
  dual_region_infra_state_key = var.dual_region_infra_state_key != "" ? (
    var.dual_region_infra_state_key
  ) : "dual-region/infra/${var.environment}.tfstate"
}

# we're consuming the remote stable state for the VPC, security groups, etc.
data "terraform_remote_state" "stable" {
  backend = "s3"
  config = {
    bucket = "zeebe-terraform-states"
    key    = local.stable_state_key
    region = "eu-west-1"
  }
}

# Optional: dual-region infra state (region 0). Only read when targeting dual-region.
data "terraform_remote_state" "dual_region_infra" {
  count   = local.is_dual_region ? 1 : 0
  backend = "s3"
  config = {
    bucket = "zeebe-terraform-states"
    key    = local.dual_region_infra_state_key
    region = "eu-west-1"
  }
}

locals {
  ecs_cluster_id = local.is_dual_region ? (
    data.terraform_remote_state.dual_region_infra[0].outputs.ecs_cluster_region_0_id
  ) : data.terraform_remote_state.stable.outputs["ecs_cluster_id"]

  vpc_private_subnets = local.is_dual_region ? (
    data.terraform_remote_state.dual_region_infra[0].outputs.vpc_region_0_private_subnets
  ) : data.terraform_remote_state.stable.outputs["vpc_private_subnets"]

  security_group_ids = local.is_dual_region ? [
    data.terraform_remote_state.dual_region_infra[0].outputs.sg_camunda_ports_region_0_id,
    data.terraform_remote_state.dual_region_infra[0].outputs.sg_package_80_443_region_0_id,
    ] : [
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_camunda_ports"],
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_packages"],
  ]

  # Registry secret lives in the stable stack (eu-west-1, same region/account as
  # dual-region region 0), so region-0 tasks can read it in both modes.
  registry_credentials_arn = data.terraform_remote_state.stable.outputs.registry_credentials_arn
}
