data "aws_vpc" "main" {
  id = data.terraform_remote_state.stable.outputs.vpc_id
}

data "aws_availability_zones" "available" {}

resource "random_password" "db_admin" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db_admin_password" {
  name                    = "${var.prefix}-aurora-admin-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_admin_password" {
  secret_id     = aws_secretsmanager_secret.db_admin_password.id
  secret_string = random_password.db_admin.result
}

module "postgresql" {
  source = "git::https://github.com/camunda/camunda-deployment-references.git//aws/modules/aurora?ref=d15e9e10b97b52052e735ab21dc449dbfe681170"

  cluster_name          = "${var.prefix}-aurora"
  availability_zones    = data.aws_availability_zones.available.names
  username              = "camunda_admin"
  password              = random_password.db_admin.result
  subnet_ids            = data.terraform_remote_state.stable.outputs.vpc_private_subnets
  cidr_blocks           = [data.aws_vpc.main.cidr_block]
  vpc_id                = data.terraform_remote_state.stable.outputs.vpc_id
  instance_class        = "db.t3.medium"
  num_instances         = 1
  default_database_name = "camunda"
}
