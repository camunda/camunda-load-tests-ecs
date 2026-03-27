terraform {
  required_version = ">= 1.7.0"
  backend "s3" {
    bucket = "zeebe-terraform-states"
    # To override this use -backend-config option with terraform init
    key    = "benchmarks/benchmark1.tfstate"
    region = "eu-west-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      managed_by = "Terraform"
      repository = "camunda/zeebe-terraform"
      folder     = "aws/benchmark"
    }
  }
}

locals {
  stable_state_key = "stable/${var.environment}/terraform.tfstate"
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
