################################################################
#                 Aurora Global Database                        #
################################################################

# Every camunda-deployment-references module in this repo is pinned to
# ab171a87 — the head of PR #2914 (branch aurora-mysql-engine-option) — rather
# than to main. On main this module hardcodes port 5432 in its security groups,
# so an aurora-mysql cluster never gets a 3306 rule, and the SGs use inline
# ingress/egress blocks, which Terraform forbids combining with standalone
# aws_security_group_rule resources — the port cannot be patched from here.
# The branch is behind main, but across every module path this repo sources
# main has changed nothing since the branch point, so nothing is lost.
# Move all the pins back to main once #2914 merges.
module "aurora_global" {
  count  = var.secondary_storage_type == "rdbms" ? 1 : 0
  source = "git::https://github.com/camunda/camunda-deployment-references.git//aws/modules/aurora-global?ref=ab171a87ec14658534bf7e518b64e06109033b0f"

  providers = {
    aws.primary   = aws
    aws.secondary = aws.accepter
  }

  global_cluster_identifier = "${local.prefix}-global-db"

  engine = var.database_engine == "mysql" ? "aurora-mysql" : "aurora-postgresql"
  # renovate: datasource=custom.aurora-mysql-camunda depName=aurora-mysql versioning=loose
  engine_version             = var.database_engine == "mysql" ? "8.4.mysql_aurora.8.4.7" : "18.3"
  auto_minor_version_upgrade = false
  database_name              = var.db_name

  master_username  = var.db_admin_username
  master_password  = local.db_admin_password_effective
  iam_auth_enabled = var.db_iam_auth_enabled

  # Primary cluster (region 0 — writer)
  primary_cluster_name       = "${local.prefix_region_0}-camunda-db"
  primary_vpc_id             = local.vpc.region_0_vpc_id
  primary_subnet_ids         = local.vpc.region_0_private_subnet_ids
  primary_cidr_blocks        = [local.vpc.region_0_vpc_cidr, local.vpc.region_1_vpc_cidr]
  primary_availability_zones = local.region_0_azs
  primary_num_instances      = 1

  # Secondary cluster (region 1 — read replicas)
  secondary_cluster_name  = "${local.prefix_region_1}-camunda-db"
  secondary_vpc_id        = local.vpc.region_1_vpc_id
  secondary_subnet_ids    = local.vpc.region_1_private_subnet_ids
  secondary_cidr_blocks   = [local.vpc.region_0_vpc_cidr, local.vpc.region_1_vpc_cidr]
  secondary_num_instances = 1
}
