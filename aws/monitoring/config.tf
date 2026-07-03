terraform {
  required_version = ">= 1.7.0"
  backend "s3" {
    bucket       = "zeebe-terraform-states"
    key = "monitoring/${var.prefix}.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      managed_by = "Terraform"
      repository = "camunda/zeebe-terraform"
      folder     = "aws/monitoring"
    }
  }
}

locals {
  # stable_state_key overrides the default dev/prod-derived key — used by the
  # us-east-1 (dual-region secondary) monitoring instance, whose aws/stable
  # state doesn't follow the dev/prod naming (see aws/stable/us-east-1).
  stable_state_key = var.stable_state_key != "" ? var.stable_state_key : "stable/${var.environment}/terraform.tfstate"
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

# Dual-region: the primary instance reads the secondary's monitoring state to
# find its Prometheus internal NLB DNS name for federation. Empty by default.
data "terraform_remote_state" "federation_peer_monitoring" {
  count   = var.federation_peer_monitoring_state_key != "" ? 1 : 0
  backend = "s3"
  config = {
    bucket = "zeebe-terraform-states"
    key    = var.federation_peer_monitoring_state_key
    region = "eu-west-1"
  }
}
