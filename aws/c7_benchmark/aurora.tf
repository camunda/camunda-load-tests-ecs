# Aurora PostgreSQL for the C7 engine (runtime and history in one database).
#
# Not using the camunda-deployment-references aurora module (used by the C8 benchmark) because it
# does not expose storage_type, Performance Insights or a parameter group. Same engine family and
# network placement, so C7 and C8 results stay comparable once both use the same instance class.

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.prefix}-c7-db-password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

resource "aws_db_subnet_group" "c7" {
  name       = "${var.prefix}-c7"
  subnet_ids = local.stable.vpc_private_subnets
}

resource "aws_security_group" "aurora" {
  name   = "${var.prefix}-c7-aurora"
  vpc_id = local.stable.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [local.stable.vpc_cidr_block]
  }
}

resource "aws_rds_cluster_parameter_group" "c7" {
  name   = "${var.prefix}-c7"
  family = "aurora-postgresql${split(".", var.aurora_engine_version)[0]}"

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "pg_stat_statements.track"
    value = "all"
  }
  parameter {
    name  = "track_io_timing"
    value = "1"
  }
}

resource "aws_rds_cluster" "c7" {
  cluster_identifier              = "${var.prefix}-c7"
  engine                          = "aurora-postgresql"
  engine_version                  = var.aurora_engine_version
  storage_type                    = var.aurora_storage_type
  database_name                   = "camunda"
  master_username                 = "camunda"
  master_password                 = random_password.db.result
  db_subnet_group_name            = aws_db_subnet_group.c7.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.c7.name
  skip_final_snapshot             = true
  deletion_protection             = false
  apply_immediately               = true
  backup_retention_period         = 1
}

resource "aws_rds_cluster_instance" "c7" {
  identifier                   = "${var.prefix}-c7-1"
  cluster_identifier           = aws_rds_cluster.c7.id
  instance_class               = var.aurora_instance_class
  engine                       = aws_rds_cluster.c7.engine
  engine_version               = aws_rds_cluster.c7.engine_version
  db_subnet_group_name         = aws_db_subnet_group.c7.name
  performance_insights_enabled = true
  apply_immediately            = true
}
