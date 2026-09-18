# Storage-branch tests for terraform/infra/.
#
# secondary_storage_type toggles between Aurora Global (RDBMS) and OpenSearch.
# This file asserts that:
#   - The right modules are instantiated (one path active, the other empty).
#   - The RDS IAM DB-connect policy only exists in RDBMS mode.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "accepter"
}

override_data {
  target = data.terraform_remote_state.vpc
  values = {
    outputs = {
      region_0_vpc_id                  = "vpc-aaaaaaaa"
      region_0_vpc_cidr                = "10.50.0.0/16"
      region_0_private_subnet_ids      = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
      region_0_public_subnet_ids       = ["subnet-aaa4aaaa", "subnet-aaa5aaaa", "subnet-aaa6aaaa"]
      region_0_private_route_table_ids = ["rtb-aaa1aaaa"]
      region_1_vpc_id                  = "vpc-bbbbbbbb"
      region_1_vpc_cidr                = "10.60.0.0/16"
      region_1_private_subnet_ids      = ["subnet-bbb1bbbb", "subnet-bbb2bbbb", "subnet-bbb3bbbb"]
      region_1_public_subnet_ids       = ["subnet-bbb4bbbb", "subnet-bbb5bbbb", "subnet-bbb6bbbb"]
      region_1_private_route_table_ids = ["rtb-bbb1bbbb"]
      networking_mode                  = "transit_gateway"
    }
  }
}

variables {
  cluster_name = "test-infra"
}

run "rdbms_creates_aurora_only" {
  command = plan

  variables {
    secondary_storage_type = "rdbms"
  }

  assert {
    condition     = length(module.aurora_global) == 1
    error_message = "Aurora Global module should be instantiated when secondary_storage_type = rdbms"
  }

  assert {
    condition     = length(module.opensearch_region_0) == 0
    error_message = "OpenSearch region 0 module should be empty when secondary_storage_type = rdbms"
  }

  assert {
    condition     = length(module.opensearch_region_1) == 0
    error_message = "OpenSearch region 1 module should be empty when secondary_storage_type = rdbms"
  }
}

run "opensearch_creates_search_only" {
  command = plan

  variables {
    secondary_storage_type = "opensearch"
  }

  assert {
    condition     = length(module.aurora_global) == 0
    error_message = "Aurora Global module should be empty when secondary_storage_type = opensearch"
  }

  assert {
    condition     = length(module.opensearch_region_0) == 1
    error_message = "OpenSearch region 0 module should be instantiated when secondary_storage_type = opensearch"
  }

  assert {
    condition     = length(module.opensearch_region_1) == 1
    error_message = "OpenSearch region 1 module should be instantiated when secondary_storage_type = opensearch"
  }
}

run "rds_db_connect_policy_only_when_rdbms" {
  command = plan

  variables {
    secondary_storage_type = "rdbms"
  }

  assert {
    condition     = length(aws_iam_policy.rds_db_connect_region_0) == 1
    error_message = "rds_db_connect_region_0 policy should exist when secondary_storage_type = rdbms"
  }

  assert {
    condition     = length(aws_iam_policy.rds_db_connect_region_1) == 1
    error_message = "rds_db_connect_region_1 policy should exist when secondary_storage_type = rdbms"
  }
}

run "rds_db_connect_policy_absent_when_opensearch" {
  command = plan

  variables {
    secondary_storage_type = "opensearch"
  }

  assert {
    condition     = length(aws_iam_policy.rds_db_connect_region_0) == 0
    error_message = "rds_db_connect_region_0 policy should NOT exist when secondary_storage_type = opensearch"
  }

  assert {
    condition     = length(aws_iam_policy.rds_db_connect_region_1) == 0
    error_message = "rds_db_connect_region_1 policy should NOT exist when secondary_storage_type = opensearch"
  }
}

# Storage-conditional outputs must keep a stable (non-null) shape: Terraform omits
# null root outputs from the remote state, which breaks app/'s local.infra lookups.
run "storage_outputs_are_never_null" {
  command = plan

  variables {
    secondary_storage_type = "opensearch"
  }

  assert {
    condition     = output.rds_db_connect_policy_region_0_arn == "" && output.rds_db_connect_policy_region_1_arn == ""
    error_message = "rds_db_connect_policy outputs should be \"\" (not null) when secondary_storage_type = opensearch"
  }

  assert {
    condition     = output.aurora_jdbc_url == "" && output.aurora_primary_endpoint == "" && output.aurora_global_cluster_id == ""
    error_message = "aurora outputs should be \"\" (not null) when secondary_storage_type = opensearch"
  }
}

run "opensearch_outputs_are_never_null_in_rdbms_mode" {
  command = plan

  variables {
    secondary_storage_type = "rdbms"
  }

  assert {
    condition     = output.opensearch_region_0_endpoint == "" && output.opensearch_region_1_endpoint == ""
    error_message = "opensearch endpoint outputs should be \"\" (not null) when secondary_storage_type = rdbms"
  }
}
