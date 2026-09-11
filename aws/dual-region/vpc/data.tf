################################################################
#      BYO-VPC: consume the existing aws/stable deployments     #
################################################################
# Region 0 (primary) reuses the existing eu-west-1 stable VPC so the
# dual-region brokers land next to the already-deployed Prometheus.
# Region 1 (secondary) reuses the us-east-1 stable VPC stood up
# specifically for this dual-region test (see aws/stable/us-east-1).
#
# Both are read directly from remote state rather than pasted as
# literal IDs, so this config can never drift from the actual
# stable deployments. Only used when byo_vpc = true.

data "terraform_remote_state" "stable_region_0" {
  count   = var.byo_vpc ? 1 : 0
  backend = "s3"

  config = {
    bucket = "zeebe-terraform-states"
    key    = var.stable_region_0_state_key
    region = "eu-west-1"
  }
}

data "terraform_remote_state" "stable_region_1" {
  count   = var.byo_vpc ? 1 : 0
  backend = "s3"

  config = {
    bucket = "zeebe-terraform-states"
    key    = var.stable_region_1_state_key
    region = "eu-west-1"
  }
}
