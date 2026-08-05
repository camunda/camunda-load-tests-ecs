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
  region = local.provider_region

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
  # In dual-region mode, target region_0 (default) or region_1 by dual_region_index.
  use_region_1 = var.dual_region && var.dual_region_index == 1
  # Default cluster name matches dual-region/infra's own default (BENCHMARK_NAME=camunda-dr).
  dual_region_infra_state_key = var.dual_region_infra_state_key != "" ? (
    var.dual_region_infra_state_key
  ) : "dual-region/infra/${var.environment}-camunda-dr.tfstate"

  provider_region = local.selected.provider_region
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
  count   = var.dual_region ? 1 : 0
  backend = "s3"
  config = {
    bucket = "zeebe-terraform-states"
    key    = local.dual_region_infra_state_key
    region = "eu-west-1"
  }
}

locals {
  # Index of the dual-region region we target; only meaningful when dual_region.
  dual_region_suffix = local.use_region_1 ? "1" : "0"

  # Select the source stack once and read every field off it, so the
  # dual-region / stable branches can never disagree per field.
  # Provider region in dual-region mode comes from the infra state's own region
  # output so it can never mismatch the cluster ARN; single-region mode uses
  # var.aws_region (default eu-west-1).
  selected = var.dual_region ? {
    provider_region     = data.terraform_remote_state.dual_region_infra[0].outputs["region_${local.dual_region_suffix}"]
    ecs_cluster_id      = data.terraform_remote_state.dual_region_infra[0].outputs["ecs_cluster_region_${local.dual_region_suffix}_id"]
    vpc_private_subnets = data.terraform_remote_state.dual_region_infra[0].outputs["vpc_region_${local.dual_region_suffix}_private_subnets"]
    security_group_ids = [
      data.terraform_remote_state.dual_region_infra[0].outputs["sg_camunda_ports_region_${local.dual_region_suffix}_id"],
      data.terraform_remote_state.dual_region_infra[0].outputs["sg_package_80_443_region_${local.dual_region_suffix}_id"],
    ]
    } : {
    provider_region     = var.aws_region
    ecs_cluster_id      = data.terraform_remote_state.stable.outputs["ecs_cluster_id"]
    vpc_private_subnets = data.terraform_remote_state.stable.outputs["vpc_private_subnets"]
    security_group_ids = [
      data.terraform_remote_state.stable.outputs.security_groups_id["allow_camunda_ports"],
      data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_packages"],
    ]
  }

  ecs_cluster_id      = local.selected.ecs_cluster_id
  vpc_private_subnets = local.selected.vpc_private_subnets
  security_group_ids  = local.selected.security_group_ids

  # Registry secret must live in the same region as the tasks. region_0 shares
  # eu-west-1 with the stable stack; region_1 uses the dual-region region_1 secret.
  registry_credentials_arn = local.use_region_1 ? (
    data.terraform_remote_state.dual_region_infra[0].outputs.registry_credentials_region_1_arn
  ) : data.terraform_remote_state.stable.outputs.registry_credentials_arn
}
