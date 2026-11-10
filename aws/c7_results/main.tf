# Long-lived S3 bucket for C7 benchmark results. Separate state from the per-run c7_benchmark
# layer, so destroying a benchmark keeps its results.
#
#   terraform init -backend-config="key=dev/c7/results-bucket.tfstate"
#   terraform apply -var environment=dev

terraform {
  required_version = ">= 1.7.0"
  backend "s3" {
    bucket = "zeebe-terraform-states"
    key    = "dev/c7/results-bucket.tfstate"
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
      repository = "camunda/camunda-load-tests-ecs"
      folder     = "aws/c7_results"
    }
  }
}

variable "environment" {
  type = string
}

resource "aws_s3_bucket" "results" {
  bucket = "camunda-c7-benchmark-results-${var.environment}"
}

resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket                  = aws_s3_bucket.results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket" {
  value = aws_s3_bucket.results.bucket
}
