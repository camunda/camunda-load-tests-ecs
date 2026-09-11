################################################################
#                  BYO-VPC Validation Checks                    #
################################################################
#
# byo_vpc = true sources both regions' VPCs from aws/stable remote state
# (see data.tf) rather than manually-pasted IDs. This check just confirms
# the sourced stable state actually satisfies the contract the rest of
# this module assumes (≥3 private + ≥3 public subnets per region, at
# least one private route table to attach cross-region routes to).

check "byo_vpc_stable_state_shape" {
  assert {
    condition = !var.byo_vpc || (
      length(data.terraform_remote_state.stable_region_0[0].outputs.vpc_private_subnets) >= 3 &&
      length(data.terraform_remote_state.stable_region_0[0].outputs.vpc_public_subnets) >= 3 &&
      length(data.terraform_remote_state.stable_region_0[0].outputs.vpc_private_route_table_ids) >= 1 &&
      length(data.terraform_remote_state.stable_region_1[0].outputs.vpc_private_subnets) >= 3 &&
      length(data.terraform_remote_state.stable_region_1[0].outputs.vpc_public_subnets) >= 3 &&
      length(data.terraform_remote_state.stable_region_1[0].outputs.vpc_private_route_table_ids) >= 1
    )
    error_message = <<-EOT
      byo_vpc = true requires both stable_region_0_state_key and
      stable_region_1_state_key to point at aws/stable deployments with
      ≥3 private + ≥3 public subnets (across distinct AZs) and ≥1 private
      route table. Check the state keys and that both aws/stable
      environments have been applied.
    EOT
  }
}
