# Dual-region cross-region networking (VPC peering) between the existing
# eu-west-1 stable VPC (region_0, primary) and the us-east-1 stable VPC
# (region_1, secondary — simulates a far region).
cluster_name    = "dev-camunda-dr"
region_0        = "eu-west-1"
region_1        = "us-east-1"
networking_mode = "vpc_peering"

byo_vpc                   = true
stable_region_0_state_key = "stable/dev/terraform.tfstate"
stable_region_1_state_key = "stable/us-east-1/terraform.tfstate"
