################################################################
#       DB Seed Task (Region 0 only — writer endpoint)         #
################################################################

resource "aws_cloudwatch_log_group" "db_seed" {
  count             = var.secondary_storage_type == "rdbms" && var.db_seed_enabled ? 1 : 0
  name              = "/ecs/${local.prefix_region_0}-db-seed"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "db_seed" {
  count                    = var.secondary_storage_type == "rdbms" && var.db_seed_enabled ? 1 : 0
  family                   = "${local.prefix_region_0}-db-seed"
  execution_role_arn       = aws_iam_role.ecs_task_execution_region_0.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = 256
  memory = 512

  container_definitions = jsonencode([
    {
      name      = "db-seed"
      image     = local.db_seed_image
      essential = true

      entryPoint = ["/bin/sh", "-lc"]
      command    = [local.db_seed_command]

      environment = [
        { name = "AURORA_ENDPOINT", value = module.aurora_global[0].primary_cluster_endpoint },
        { name = "AURORA_PORT", value = tostring(local.database_port) },
        { name = "AURORA_DB_NAME", value = var.db_name },
        { name = "AURORA_ADMIN_USERNAME", value = var.db_admin_username },
        { name = "IAM_DB_USERS", value = join(" ", var.db_seed_iam_usernames) }
      ]

      secrets = [
        {
          name      = "AURORA_ADMIN_PASSWORD"
          valueFrom = aws_secretsmanager_secret.db_admin_password_region_0.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.db_seed[0].name
          awslogs-region        = data.aws_region.region_0.id
          awslogs-stream-prefix = "db-seed"
        }
      }
    }
  ])

  depends_on = [module.aurora_global]
}

resource "null_resource" "run_db_seed_task" {
  count = var.secondary_storage_type == "rdbms" && var.db_seed_enabled ? 1 : 0

  triggers = {
    aurora_endpoint = module.aurora_global[0].primary_cluster_endpoint
    db_name         = var.db_name
    iam_users       = join(",", var.db_seed_iam_usernames)
    iam_auth        = tostring(var.db_iam_auth_enabled)
    run_id          = var.db_seed_run_id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    environment = var.aws_profile != null ? {
      AWS_PROFILE = var.aws_profile
    } : {}
    command = <<-EOT
      set -euo pipefail

      if [ "${var.db_iam_auth_enabled}" != "true" ]; then
        echo "db_seed_enabled=true but db_iam_auth_enabled=false; seeding still runs."
      fi

      if [ -z "${join(" ", var.db_seed_iam_usernames)}" ]; then
        echo "db_seed_enabled=true but db_seed_iam_usernames is empty; nothing to do."
        exit 0
      fi

      NETWORK_CONF='{"awsvpcConfiguration":{"subnets":${jsonencode(local.vpc.region_0_private_subnet_ids)},"securityGroups":${jsonencode([aws_security_group.camunda_ports_region_0.id, aws_security_group.package_80_443_region_0.id])},"assignPublicIp":"DISABLED"}}'

      echo "Running one-time DB seed task..."
      TASK_ARN=$(aws ecs run-task \
        --region "${data.aws_region.region_0.id}" \
        --cluster "${aws_ecs_cluster.region_0.arn}" \
        --launch-type FARGATE \
        --task-definition "${aws_ecs_task_definition.db_seed[0].arn}" \
        --network-configuration "$NETWORK_CONF" \
        --query 'tasks[0].taskArn' \
        --output text)

      echo "Task started: $TASK_ARN"

      aws ecs wait tasks-stopped \
        --region "${data.aws_region.region_0.id}" \
        --cluster "${aws_ecs_cluster.region_0.arn}" \
        --tasks "$TASK_ARN"

      EXIT_CODE=$(aws ecs describe-tasks \
        --region "${data.aws_region.region_0.id}" \
        --cluster "${aws_ecs_cluster.region_0.arn}" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].containers[0].exitCode' \
        --output text)

      STOP_REASON=$(aws ecs describe-tasks \
        --region "${data.aws_region.region_0.id}" \
        --cluster "${aws_ecs_cluster.region_0.arn}" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].stoppedReason' \
        --output text)

      if [ "$EXIT_CODE" != "0" ]; then
        echo "DB seed task failed with exit code $EXIT_CODE. stoppedReason=$STOP_REASON"
        echo "Check logs in CloudWatch log group: /ecs/${local.prefix_region_0}-db-seed"
        exit 1
      fi

      echo "DB seed task succeeded."
    EOT
  }

  depends_on = [
    module.aurora_global,
    aws_ecs_cluster.region_0,
    aws_ecs_task_definition.db_seed,
  ]
}
