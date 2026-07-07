locals {
  # Use registry credentials when provided
  use_registry_credentials = var.registry_username != "" && var.registry_password != ""

  # Only emit repositoryCredentials when we have an ARN; an empty
  # credentialsParameter is rejected by RegisterTaskDefinition.
  repository_credentials = local.registry_credentials_arn != "" ? {
    repositoryCredentials = { credentialsParameter = local.registry_credentials_arn }
  } : {}

  # Determine if this is an ECR image (no registry credentials needed)
  is_ecr_image = strcontains(var.camunda_image, ".dkr.ecr.") && strcontains(var.camunda_image, ".amazonaws.com")

  # Client endpoints. Default to the Cloud Map DNS derived from camunda_host; override
  # (e.g. to a region_0 load balancer) by setting grpc_address / rest_address explicitly.
  grpc_address = var.grpc_address != "" ? var.grpc_address : "http://${var.camunda_host}:26500"
  rest_address = var.rest_address != "" ? var.rest_address : "http://${var.camunda_host}:8080"

  # Basic auth is enabled only when both a username and a password secret are provided.
  # Regular (unprotected-API) benchmarks leave these empty and run without auth.
  use_basic_auth = var.camunda_auth_username != "" && var.camunda_auth_password_secret_arn != ""

  basic_auth_env = local.use_basic_auth ? [
    { name = "CAMUNDA_CLIENT_MODE", value = "self-managed" },
    { name = "CAMUNDA_CLIENT_AUTH_METHOD", value = "basic" },
    { name = "CAMUNDA_CLIENT_AUTH_USERNAME", value = var.camunda_auth_username },
  ] : []

  basic_auth_secrets = local.use_basic_auth ? [
    { name = "CAMUNDA_CLIENT_AUTH_PASSWORD", valueFrom = var.camunda_auth_password_secret_arn },
  ] : []
}

# Registry credentials  
resource "aws_secretsmanager_secret" "registry_credentials" {
  count       = local.use_registry_credentials ? 1 : 0
  name        = "${var.prefix}-registry-credentials"
  description = "Registry credentials for ECS tasks"
}

resource "aws_secretsmanager_secret_version" "registry_credentials" {
  count     = local.use_registry_credentials ? 1 : 0
  secret_id = aws_secretsmanager_secret.registry_credentials[0].id
  secret_string = jsonencode({
    username = var.registry_username
    password = var.registry_password
  })
}
# Starter task definition (Zeebe client load generator)
resource "aws_ecs_task_definition" "starter" {
  family                   = "${var.prefix}-starter"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024

  container_definitions = jsonencode([
    merge(local.repository_credentials, {
      name      = "starter"
      image     = var.starter_image
      essential = true
      environment = concat([
        { name = "CAMUNDA_CLIENT_GRPC_ADDRESS", value = local.grpc_address },
        { name = "CAMUNDA_CLIENT_REST_ADDRESS", value = local.rest_address },
        { name = "CAMUNDA_CLIENT_PREFER_REST_OVER_GRPC", value = var.prefer_rest_over_grpc },
        { name = "LOAD_TESTER_MONITOR_DATA_AVAILABILITY", value = "false" },
        { name = "LOAD_TESTER_STARTER_RATE", value = "150" },
        { name = "LOAD_TESTER_STARTER_DURATION_LIMIT", value = "0" },
        { name = "LOAD_TESTER_STARTER_PROCESS_ID", value = "benchmark" },
        { name = "LOAD_TESTER_STARTER_BPMN_XML_PATH", value = "bpmn/one_task.bpmn" },
        { name = "LOAD_TESTER_STARTER_BUSINESS_KEY", value = "businessKey" },
        { name = "LOAD_TESTER_STARTER_PAYLOAD_PATH", value = "bpmn/typical_payload.json" },
        { name = "JDK_JAVA_OPTIONS", value = "-XX:+HeapDumpOnOutOfMemoryError" },
        { name = "CAMUNDA_LOG_LEVEL", value = "INFO" },
        { name = "LOG_LEVEL", value = "INFO" }
      ], local.basic_auth_env)
      secrets = local.basic_auth_secrets
      portMappings = [
        { containerPort = 9600, hostPort = 9600, protocol = "tcp" }
      ],

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.load_test1_log_group.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "starter"
        }
      }
    })
  ])
}

# Starter service (no public exposure, single task)
resource "aws_ecs_service" "starter" {
  name                   = "${var.prefix}-starter-service"
  cluster                = local.ecs_cluster_id
  task_definition        = aws_ecs_task_definition.starter.arn
  desired_count          = 1
  force_new_deployment   = var.force_new_deployment
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = local.vpc_private_subnets
    security_groups  = local.security_group_ids
    assign_public_ip = false
  }
}


# Worker task definition (Zeebe job worker)
resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.prefix}-worker"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    merge(local.repository_credentials, {
      name      = "worker"
      image     = var.worker_image
      essential = true
      environment = concat([
        { name = "SPRING_PROFILES_ACTIVE", value = "worker" },
        { name = "CAMUNDA_CLIENT_GRPC_ADDRESS", value = local.grpc_address },
        { name = "CAMUNDA_CLIENT_REST_ADDRESS", value = local.rest_address },
        { name = "CAMUNDA_CLIENT_PREFER_REST_OVER_GRPC", value = var.prefer_rest_over_grpc },
        { name = "CAMUNDA_CLIENT_WORKER_DEFAULTS_MAX_JOBS_ACTIVE", value = "60" },
        { name = "CAMUNDA_CLIENT_EXECUTION_THREADS", value = "10" },
        { name = "CAMUNDA_CLIENT_WORKER_DEFAULTS_POLL_INTERVAL", value = "1ms" },
        { name = "LOAD_TESTER_WORKER_COMPLETION_DELAY", value = "50ms" },
        { name = "CAMUNDA_CLIENT_WORKER_DEFAULTS_NAME", value = "worker" },
        { name = "CAMUNDA_CLIENT_WORKER_DEFAULTS_TYPE", value = "benchmark-task" },
        { name = "LOAD_TESTER_WORKER_PAYLOAD_PATH", value = "bpmn/typical_payload.json" },
        { name = "JDK_JAVA_OPTIONS", value = "-XX:+HeapDumpOnOutOfMemoryError" },
        { name = "LOAD_TESTER_LOG_APPENDER", value = "Stackdriver" },
        { name = "LOG_LEVEL", value = "INFO" }
      ], local.basic_auth_env)
      secrets = local.basic_auth_secrets
      portMappings = [
        { containerPort = 9600, hostPort = 9600, protocol = "tcp" }
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.load_test1_log_group.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "worker"
        }
      }
    })
  ])
}

# Worker service (internal only, 3 replicas)
resource "aws_ecs_service" "worker" {
  name            = "${var.prefix}-worker-service"
  cluster         = local.ecs_cluster_id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 3

  force_new_deployment   = var.force_new_deployment
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = local.vpc_private_subnets
    security_groups  = local.security_group_ids
    assign_public_ip = false
  }
}

