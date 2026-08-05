################################
# Computed Values             #
################################

resource "random_id" "bucket_suffix" {
  byte_length = 3 # 6 hex characters
}

locals {
  prefix        = var.cluster_name
  bucket_suffix = random_id.bucket_suffix.hex

  # Truncate prefix for AWS resources with name length limits (e.g., ALB target groups: 32 chars)
  prefix_truncated = substr(local.prefix, 0, 14)

  # Region-specific prefixes
  prefix_region_0 = "${local.prefix}-r0"
  prefix_region_1 = "${local.prefix}-r1"

  # Load balancer ingress CIDRs, resolved per region. Each region's SG must allow
  # its *own* VPC CIDR — the load balancers of region N live in region N's VPC, so
  # a single shared list would make one of the two regions unreachable.
  # var.limit_access_to_cidrs is additive on top (operator override, e.g. an
  # office CIDR or 0.0.0.0/0) and applies to both regions.
  remote_access_cidrs_region_0 = distinct(concat([local.vpc.region_0_vpc_cidr], var.limit_access_to_cidrs))
  remote_access_cidrs_region_1 = distinct(concat([local.vpc.region_1_vpc_cidr], var.limit_access_to_cidrs))

  database_port = var.database_engine == "mysql" ? 3306 : 5432
  db_seed_image = var.database_engine == "mysql" ? "public.ecr.aws/docker/library/mysql:8.4" : "public.ecr.aws/docker/library/postgres:17-alpine"
  db_seed_command = var.database_engine == "mysql" ? (<<-EOT
    set -euo pipefail

    if [ -z "$${IAM_DB_USERS}" ]; then
      echo "No IAM_DB_USERS provided; nothing to do."
      exit 0
    fi

    for user in $${IAM_DB_USERS}; do
      mysql --host="$${AURORA_ENDPOINT}" --port="$${AURORA_PORT}" \\
        --user="$${AURORA_ADMIN_USERNAME}" --password="$${AURORA_ADMIN_PASSWORD}" \\
        --ssl-mode=REQUIRED \\
        -e "CREATE USER IF NOT EXISTS '$${user}'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS' REQUIRE SSL; GRANT ALL PRIVILEGES ON \\`$${AURORA_DB_NAME}\\`.* TO '$${user}'@'%'; FLUSH PRIVILEGES;"
    done
  EOT
    ) : (<<-EOT
    set -euo pipefail

    if [ -z "$${IAM_DB_USERS}" ]; then
      echo "No IAM_DB_USERS provided; nothing to do."
      exit 0
    fi

    for user in $${IAM_DB_USERS}; do
      psql "host=$${AURORA_ENDPOINT} port=$${AURORA_PORT} dbname=$${AURORA_DB_NAME} user=$${AURORA_ADMIN_USERNAME} password=$${AURORA_ADMIN_PASSWORD} sslmode=require" \\
        -v ON_ERROR_STOP=1 \\
        -c "DO \\$\\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$${user}') THEN CREATE ROLE \\\"$${user}\\\" WITH LOGIN; END IF; END \\$\\$;" \\
        -c "GRANT rds_iam TO \\\"$${user}\\\";" \\
        -c "GRANT ALL PRIVILEGES ON DATABASE \\\"$${AURORA_DB_NAME}\\\" TO \\\"$${user}\\\";" \\
        -c "GRANT USAGE, CREATE ON SCHEMA public TO \\\"$${user}\\\";"
    done
  EOT
  )

  # AZs of the private subnets, derived from the vpc/ outputs.
  # Used by Aurora to populate the cluster's availability_zones argument.
  region_0_azs = distinct([for s in data.aws_subnet.region_0_private : s.availability_zone])
  region_1_azs = distinct([for s in data.aws_subnet.region_1_private : s.availability_zone])

  # Registry credentials ARN actually used per region: the manual secret when
  # registry_username is explicitly set, otherwise the Vault-synced creds from
  # the stable stack (always populated). Shared by the outputs and the task
  # execution role IAM policies below.
  registry_credentials_region_0_arn = var.registry_username != "" ? aws_secretsmanager_secret.registry_credentials_region_0[0].arn : data.terraform_remote_state.stable.outputs.registry_credentials_arn
  registry_credentials_region_1_arn = var.registry_username != "" ? aws_secretsmanager_secret.registry_credentials_region_1[0].arn : data.terraform_remote_state.stable_us_east_1.outputs.registry_credentials_arn
}
