################################
# Backend & Provider Setup    #
################################

terraform {
  required_version = ">= 1.7.0"

  backend "s3" {
    bucket       = "zeebe-terraform-states"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region  = local.infra.region_0
  profile = var.aws_profile
  default_tags {
    tags = var.default_tags
  }
}

provider "aws" {
  region  = local.infra.region_1
  alias   = "accepter"
  profile = var.aws_profile
  default_tags {
    tags = var.default_tags
  }
}
