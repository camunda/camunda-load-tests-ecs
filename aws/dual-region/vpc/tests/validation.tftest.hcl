# Validation tests for aws/dual-region/vpc.
#
# Covers the per-variable validation rules that still exist plus the single
# cross-cutting check block in byo.tf (check.byo_vpc_stable_state_shape).
# Every test uses expect_failures to assert a SPECIFIC rule fires — never a
# blanket failure, otherwise a regression that breaks the wrong thing would
# still pass.
#
# These tests use mock_provider and override_data so no AWS calls are made.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "accepter"
}

# Override AZ data sources so greenfield-mode runs have deterministic AZs.
override_data {
  target = data.aws_availability_zones.region_0[0]
  values = {
    names = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }
}

override_data {
  target = data.aws_availability_zones.region_1[0]
  values = {
    names = ["us-east-2a", "us-east-2b", "us-east-2c"]
  }
}

# Deliberately undersized stable state: only 2 private subnets per region,
# which violates the ≥3 contract asserted by check.byo_vpc_stable_state_shape.
override_data {
  target = data.terraform_remote_state.stable_region_0[0]
  values = {
    outputs = {
      vpc_id                      = "vpc-aaaaaaaa"
      vpc_cidr_block              = "10.50.0.0/16"
      vpc_private_subnets         = ["subnet-aaa1aaaa", "subnet-aaa2aaaa"]
      vpc_public_subnets          = ["subnet-aaa4aaaa", "subnet-aaa5aaaa", "subnet-aaa6aaaa"]
      vpc_private_route_table_ids = ["rtb-aaa1aaaa"]
    }
  }
}

override_data {
  target = data.terraform_remote_state.stable_region_1[0]
  values = {
    outputs = {
      vpc_id                      = "vpc-bbbbbbbb"
      vpc_cidr_block              = "10.60.0.0/16"
      vpc_private_subnets         = ["subnet-bbb1bbbb", "subnet-bbb2bbbb"]
      vpc_public_subnets          = ["subnet-bbb4bbbb", "subnet-bbb5bbbb", "subnet-bbb6bbbb"]
      vpc_private_route_table_ids = ["rtb-bbb1bbbb"]
    }
  }
}

variables {
  cluster_name = "test-validation"
}

# ------------------- Cross-variable: check.byo_vpc_stable_state_shape -------------------

run "byo_vpc_stable_state_shape_fails_when_subnets_below_minimum" {
  command = plan

  variables {
    byo_vpc = true
  }

  expect_failures = [
    check.byo_vpc_stable_state_shape,
  ]
}

# ------------------- Per-variable validation -------------------

run "region_0_cidr_validation_rejects_garbage" {
  command = plan

  variables {
    region_0_cidr = "not-a-cidr"
  }

  expect_failures = [
    var.region_0_cidr,
  ]
}

run "region_1_cidr_validation_rejects_garbage" {
  command = plan

  variables {
    region_1_cidr = "not-a-cidr"
  }

  expect_failures = [
    var.region_1_cidr,
  ]
}

run "networking_mode_rejects_invalid" {
  command = plan

  variables {
    networking_mode = "magic_network"
  }

  expect_failures = [
    var.networking_mode,
  ]
}
