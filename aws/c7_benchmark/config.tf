terraform {
  required_version = ">= 1.7.0"
  backend "s3" {
    bucket = "zeebe-terraform-states"
    # Overridden per run with -backend-config (see shared.mk)
    key    = "dev/c7/c7-benchmark1.tfstate"
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
      repository = "camunda/camunda-load-tests-ecs"
      folder     = "aws/c7_benchmark"
      benchmark  = var.prefix
    }
  }
}

locals {
  stable_state_key = "stable/${var.environment}/terraform.tfstate"
  stable           = data.terraform_remote_state.stable.outputs
  # Cloud Map namespace; the monitoring discovery picks up *-c7.service.local.
  namespace_name = "${var.prefix}-c7.service.local"
  engine_host    = "engine.${local.namespace_name}"
  # Value of the Prometheus `namespace` label, matching the C8 convention "ecs-<benchmark>-oc".
  metrics_namespace = "ecs-${var.prefix}-c7"
}

# VPC, subnets, security groups, ECS cluster and registry credentials from the shared stable layer.
data "terraform_remote_state" "stable" {
  backend = "s3"
  config = {
    bucket = "zeebe-terraform-states"
    key    = local.stable_state_key
    region = "eu-west-1"
  }
}

data "aws_region" "current" {}
