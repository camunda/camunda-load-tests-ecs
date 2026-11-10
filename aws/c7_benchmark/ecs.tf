# ECS services of the C7 benchmark: engine, starter, worker, postgres-exporter.
# All register in the Cloud Map namespace <prefix>-c7.service.local, which the monitoring
# discovery scrapes (see the c7 job in aws/monitoring).

locals {
  registry_credentials = { credentialsParameter = local.stable.registry_credentials_arn }

  log_config = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.c7.name
      awslogs-region        = data.aws_region.current.region
      awslogs-stream-prefix = "c7"
    }
  }

  jdbc_url = "jdbc:postgresql://${aws_rds_cluster.c7.endpoint}:5432/camunda"

  services = {
    engine = {
      count  = var.engine_count
      cpu    = var.engine_cpu
      memory = var.engine_memory
      container = {
        name                  = "engine"
        image                 = var.engine_image
        repositoryCredentials = local.registry_credentials
        essential             = true
        portMappings          = [{ containerPort = 8080 }, { containerPort = 9600 }]
        environment = [
          { name = "DB_URL", value = local.jdbc_url },
          { name = "DB_USERNAME", value = "camunda" },
          { name = "DB_POOL_SIZE", value = tostring(var.engine_db_pool_size) },
          { name = "HISTORY_LEVEL", value = var.history_level },
          { name = "SPRING_PROFILES_ACTIVE", value = var.history_cleanup ? "history-cleanup" : "default" },
          { name = "COCKPIT_ENABLED", value = tostring(var.cockpit_enabled) },
          { name = "JAVA_OPTS", value = "-XX:MaxRAMPercentage=70 -XX:+UseG1GC" },
        ]
        secrets          = [{ name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn }]
        logConfiguration = local.log_config
      }
    }

    starter = {
      count  = 1
      cpu    = 1024
      memory = 2048
      container = {
        name                  = "starter"
        image                 = var.load_tester_image
        repositoryCredentials = local.registry_credentials
        essential             = true
        portMappings          = [{ containerPort = 9600 }]
        environment = [
          { name = "SPRING_PROFILES_ACTIVE", value = "starter" },
          { name = "ENGINE_URL", value = "http://${local.engine_host}:8080" },
          { name = "LOAD_TESTER_STARTER_RATE", value = tostring(var.starter_rate) },
          { name = "LOAD_TESTER_STARTER_PAYLOAD_PATH", value = var.starter_payload_path },
          { name = "LOAD_TESTER_STARTER_DURATION_LIMIT", value = tostring(var.starter_duration_limit) },
        ]
        logConfiguration = local.log_config
      }
    }

    worker = {
      count  = var.worker_count
      cpu    = 512
      memory = 1024
      container = {
        name                  = "worker"
        image                 = var.load_tester_image
        repositoryCredentials = local.registry_credentials
        essential             = true
        portMappings          = [{ containerPort = 9600 }]
        environment = [
          { name = "SPRING_PROFILES_ACTIVE", value = "worker" },
          { name = "ENGINE_URL", value = "http://${local.engine_host}:8080" },
          { name = "LOAD_TESTER_WORKER_CAPACITY", value = tostring(var.worker_capacity) },
          { name = "LOAD_TESTER_WORKER_THREADS", value = tostring(var.worker_threads) },
          { name = "LOAD_TESTER_WORKER_COMPLETION_DELAY", value = var.worker_completion_delay },
          { name = "LOAD_TESTER_WORKER_PAYLOAD_PATH", value = var.starter_payload_path },
        ]
        logConfiguration = local.log_config
      }
    }

    # Same queries as CNPG on GKE (camunda/camunda load-tests/c7/monitor/postgres/queries.yaml,
    # copied to files/; keep in sync), passed as an env var because
    # Fargate has no bind mounts. pg_stat_wal is not available on Aurora; use CloudWatch instead.
    postgres-exporter = {
      count  = 1
      cpu    = 256
      memory = 512
      container = {
        name         = "postgres-exporter"
        image        = var.postgres_exporter_image
        essential    = true
        portMappings = [{ containerPort = 9187 }]
        entryPoint   = ["/bin/sh", "-c"]
        command      = ["printf '%s' \"$C7_QUERIES\" > /tmp/queries.yaml && exec /bin/postgres_exporter --extend.query-path=/tmp/queries.yaml"]
        environment = [
          { name = "DATA_SOURCE_URI", value = "${aws_rds_cluster.c7.endpoint}:5432/camunda?sslmode=require" },
          { name = "DATA_SOURCE_USER", value = "camunda" },
          { name = "C7_QUERIES", value = file("${path.module}/files/postgres-queries.yaml") },
        ]
        secrets          = [{ name = "DATA_SOURCE_PASS", valueFrom = aws_secretsmanager_secret.db_password.arn }]
        logConfiguration = local.log_config
      }
    }
  }
}

resource "aws_cloudwatch_log_group" "c7" {
  name              = "/ecs/${var.prefix}-c7"
  retention_in_days = 3
}

resource "aws_service_discovery_private_dns_namespace" "c7" {
  name        = local.namespace_name
  vpc         = local.stable.vpc_id
  description = "C7 benchmark ${var.prefix}"
}

resource "aws_service_discovery_service" "c7" {
  for_each = local.services
  name     = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.c7.id
    dns_records {
      type = "A"
      ttl  = 10
    }
    routing_policy = "MULTIVALUE"
  }
}

resource "aws_security_group" "c7" {
  name   = "${var.prefix}-c7-services"
  vpc_id = local.stable.vpc_id

  # REST (engine), metrics (all apps), postgres-exporter; from inside the VPC only.
  dynamic "ingress" {
    for_each = [8080, 9600, 9187]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [local.stable.vpc_cidr_block]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_task_definition" "c7" {
  for_each                 = local.services
  family                   = "${var.prefix}-c7-${each.key}"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  container_definitions    = jsonencode([each.value.container])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}

resource "aws_ecs_service" "c7" {
  for_each               = local.services
  name                   = "${var.prefix}-c7-${each.key}"
  cluster                = local.stable.ecs_cluster_id
  task_definition        = aws_ecs_task_definition.c7[each.key].arn
  desired_count          = each.value.count
  launch_type            = "FARGATE"
  force_new_deployment   = var.force_new_deployment
  enable_execute_command = true

  network_configuration {
    subnets          = local.stable.vpc_private_subnets
    security_groups  = [aws_security_group.c7.id, local.stable.security_groups_id["allow_remote_packages"]]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.c7[each.key].arn
  }

  # The engine creates the schema on first start; start clients after the database exists.
  depends_on = [aws_rds_cluster_instance.c7]
}
