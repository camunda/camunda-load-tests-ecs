terraform {
  required_version = ">= 1.7.0"
  backend "s3" {
    bucket       = "zeebe-terraform-states"
    key = "stable/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      managed_by = "Terraform"
      repository = "github.com/camunda/zeebe-terraform"
      folder     = "aws/stable"
    }
  }
}

provider "vault" {
  # VAULT_ADDR and VAULT_TOKEN are expected from the environment.
  # Locally: export VAULT_ADDR via .envrc, authenticate with `vault login -method=oidc`
  # CI:      hashicorp/vault-action sets both automatically
}
