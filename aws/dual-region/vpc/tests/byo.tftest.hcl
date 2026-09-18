# BYO-VPC mode tests.
#
# When byo_vpc = true, the terraform-aws-modules/vpc/aws module instantiations
# are skipped (count = 0) and the VPC details are read from the aws/stable
# remote states (see data.tf). This file asserts:
#   1. Outputs match the sourced stable remote state (the contract).
#   2. No VPC module resources are planned (locals point at remote state).
#   3. Peering / TGW is still planned between the sourced VPC IDs.
#
# The remote states are overridden so the suite runs credential-free. The
# mocked `outputs` object mirrors the shape of aws/stable/outputs.tf.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "accepter"
}

override_data {
  target = data.terraform_remote_state.stable_region_0[0]
  values = {
    outputs = {
      vpc_id                          = "vpc-aaaaaaaa"
      vpc_cidr_block                  = "10.50.0.0/16"
      vpc_private_subnets             = ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
      vpc_public_subnets              = ["subnet-aaa4aaaa", "subnet-aaa5aaaa", "subnet-aaa6aaaa"]
      vpc_private_route_table_ids     = ["rtb-aaa1aaaa", "rtb-aaa2aaaa", "rtb-aaa3aaaa"]
      ecs_cluster_id                  = "arn:aws:ecs:eu-west-1:111111111111:cluster/stable-r0"
      registry_credentials_arn        = "arn:aws:secretsmanager:eu-west-1:111111111111:secret:registry-r0"
      registry_credentials_iam_policy = "arn:aws:iam::111111111111:policy/registry-r0"
      ecr_repository_url              = "111111111111.dkr.ecr.eu-west-1.amazonaws.com/camunda"
      ecr_repository_arn              = "arn:aws:ecr:eu-west-1:111111111111:repository/camunda"
      security_groups_id = {
        allow_camunda_ports   = "sg-aaa1aaaa"
        allow_remote_packages = "sg-aaa2aaaa"
        allow_efs             = "sg-aaa3aaaa"
        allow_remote_80_443   = "sg-aaa4aaaa"
        allow_remote_9600     = "sg-aaa5aaaa"
        allow_remote_grpc     = "sg-aaa6aaaa"
        allow_remote_3000     = "sg-aaa7aaaa"
      }
      ports = {}
    }
  }
}

override_data {
  target = data.terraform_remote_state.stable_region_1[0]
  values = {
    outputs = {
      vpc_id                          = "vpc-bbbbbbbb"
      vpc_cidr_block                  = "10.60.0.0/16"
      vpc_private_subnets             = ["subnet-bbb1bbbb", "subnet-bbb2bbbb", "subnet-bbb3bbbb"]
      vpc_public_subnets              = ["subnet-bbb4bbbb", "subnet-bbb5bbbb", "subnet-bbb6bbbb"]
      vpc_private_route_table_ids     = ["rtb-bbb1bbbb", "rtb-bbb2bbbb", "rtb-bbb3bbbb"]
      ecs_cluster_id                  = "arn:aws:ecs:us-east-1:111111111111:cluster/stable-r1"
      registry_credentials_arn        = "arn:aws:secretsmanager:us-east-1:111111111111:secret:registry-r1"
      registry_credentials_iam_policy = "arn:aws:iam::111111111111:policy/registry-r1"
      ecr_repository_url              = "111111111111.dkr.ecr.us-east-1.amazonaws.com/camunda"
      ecr_repository_arn              = "arn:aws:ecr:us-east-1:111111111111:repository/camunda"
      security_groups_id = {
        allow_camunda_ports   = "sg-bbb1bbbb"
        allow_remote_packages = "sg-bbb2bbbb"
        allow_efs             = "sg-bbb3bbbb"
        allow_remote_80_443   = "sg-bbb4bbbb"
        allow_remote_9600     = "sg-bbb5bbbb"
        allow_remote_grpc     = "sg-bbb6bbbb"
        allow_remote_3000     = "sg-bbb7bbbb"
      }
      ports = {}
    }
  }
}

variables {
  cluster_name = "test-byo"
  byo_vpc      = true
}

run "byo_passthrough_outputs_match_stable_remote_state" {
  command = plan

  assert {
    condition     = output.region_0_vpc_id == "vpc-aaaaaaaa"
    error_message = "region_0_vpc_id output should equal the stable_region_0 remote state vpc_id"
  }

  assert {
    condition     = output.region_0_vpc_cidr == "10.50.0.0/16"
    error_message = "region_0_vpc_cidr output should equal the stable_region_0 remote state vpc_cidr_block"
  }

  assert {
    condition     = output.region_0_private_subnet_ids == ["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"]
    error_message = "region_0_private_subnet_ids passthrough broken"
  }

  assert {
    condition     = output.region_0_public_subnet_ids == ["subnet-aaa4aaaa", "subnet-aaa5aaaa", "subnet-aaa6aaaa"]
    error_message = "region_0_public_subnet_ids passthrough broken"
  }

  assert {
    condition     = output.region_0_private_route_table_ids == ["rtb-aaa1aaaa", "rtb-aaa2aaaa", "rtb-aaa3aaaa"]
    error_message = "region_0_private_route_table_ids passthrough broken"
  }

  assert {
    condition     = output.region_1_vpc_id == "vpc-bbbbbbbb"
    error_message = "region_1_vpc_id passthrough broken"
  }

  assert {
    condition     = output.region_1_vpc_cidr == "10.60.0.0/16"
    error_message = "region_1_vpc_cidr passthrough broken"
  }

  assert {
    condition     = output.region_1_private_route_table_ids == ["rtb-bbb1bbbb", "rtb-bbb2bbbb", "rtb-bbb3bbbb"]
    error_message = "region_1_private_route_table_ids passthrough broken"
  }
}

run "byo_internet_gateway_outputs_null" {
  command = plan

  assert {
    condition     = output.region_0_internet_gateway_id == null
    error_message = "region_0_internet_gateway_id should be null in BYO mode (customer-managed)"
  }

  assert {
    condition     = output.region_1_internet_gateway_id == null
    error_message = "region_1_internet_gateway_id should be null in BYO mode (customer-managed)"
  }
}

run "byo_skips_vpc_module_region_0" {
  command = plan

  assert {
    condition     = length(module.vpc_region_0) == 0
    error_message = "module.vpc_region_0 should have count = 0 when byo_vpc = true"
  }
}

run "byo_skips_vpc_module_region_1" {
  command = plan

  assert {
    condition     = length(module.vpc_region_1) == 0
    error_message = "module.vpc_region_1 should have count = 0 when byo_vpc = true"
  }
}

run "byo_with_vpc_peering_creates_peering_between_sourced_ids" {
  command = plan

  variables {
    networking_mode = "vpc_peering"
  }

  assert {
    condition     = aws_vpc_peering_connection.cross_region[0].vpc_id == "vpc-aaaaaaaa"
    error_message = "Peering connection requester VPC should be the sourced region_0 VPC ID"
  }

  assert {
    condition     = aws_vpc_peering_connection.cross_region[0].peer_vpc_id == "vpc-bbbbbbbb"
    error_message = "Peering connection peer VPC should be the sourced region_1 VPC ID"
  }

  assert {
    condition     = length(module.transit_gateway) == 0
    error_message = "TGW module should be empty when networking_mode = vpc_peering"
  }
}

run "byo_with_transit_gateway_creates_attachments_targeting_sourced_subnets" {
  command = plan

  variables {
    networking_mode = "transit_gateway"
  }

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.region_0[0].vpc_id == "vpc-aaaaaaaa"
    error_message = "TGW attachment in region 0 should target the sourced region_0 VPC ID"
  }

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.region_0[0].subnet_ids == toset(["subnet-aaa1aaaa", "subnet-aaa2aaaa", "subnet-aaa3aaaa"])
    error_message = "TGW attachment in region 0 should use the sourced private subnets"
  }

  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.region_1[0].vpc_id == "vpc-bbbbbbbb"
    error_message = "TGW attachment in region 1 should target the sourced region_1 VPC ID"
  }

  assert {
    condition     = length(aws_vpc_peering_connection.cross_region) == 0
    error_message = "VPC peering connection should be empty when networking_mode = transit_gateway"
  }
}
