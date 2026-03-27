locals {
   # Use registry credentials when provided
  use_registry_credentials = var.registry_username != "" && var.registry_password != ""
 
  # Determine if this is an ECR image (no registry credentials needed)
  is_ecr_image = strcontains(var.camunda_image, ".dkr.ecr.") && strcontains(var.camunda_image, ".amazonaws.com")
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
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name      = "starter"
      image = var.starter_image
      repositorycredentials: {
        credentialsparameter: data.terraform_remote_state.stable.outputs.registry_credentials_arn
      },
      essential = true
      environment = [
        { name = "JDK_JAVA_OPTIONS", value = "-Dconfig.override_with_env_vars=true -Dapp.monitorDataAvailability=false -Dapp.brokerUrl=grpc://${var.camunda_host}:26500 -Dapp.brokerRestUrl=http://${var.camunda_host}:8080 -Dapp.preferRest=false -Dapp.starter.rate=150 -Dapp.starter.durationLimit=0 -Dzeebe.client.requestTimeout=62000 -Dapp.starter.processId=benchmark -Dapp.starter.bpmnXmlPath=bpmn/one_task.bpmn -Dapp.starter.businessKey=businessKey -Dapp.starter.payloadPath=bpmn/typical_payload.json -XX:+HeapDumpOnOutOfMemoryError" },
        { name = "LOG_LEVEL", value = "WARN" }
      ]
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
    }
  ])
}

# Starter service (no public exposure, single task)
resource "aws_ecs_service" "starter" {
  name            = "${var.prefix}-starter-service"
  cluster         = data.terraform_remote_state.stable.outputs["ecs_cluster_id"]
  task_definition = aws_ecs_task_definition.starter.arn
  desired_count   = 1
  force_new_deployment = var.force_new_deployment
  launch_type     = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets         = data.terraform_remote_state.stable.outputs["vpc_private_subnets"]
    security_groups = [
      data.terraform_remote_state.stable.outputs.security_groups_id["allow_camunda_ports"],
      data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_packages"],
    ]
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
    {
      name      = "worker"
      image = var.worker_image
      repositorycredentials: {
        credentialsparameter: data.terraform_remote_state.stable.outputs.registry_credentials_arn
      },
      essential = true
      environment = [
        { name = "JDK_JAVA_OPTIONS", value = "-Dconfig.override_with_env_vars=true  -Dapp.brokerUrl=grpc://${var.camunda_host}:26500 -Dapp.brokerRestUrl=http://${var.camunda_host}:8080 -Dapp.preferRest=false -Dzeebe.client.requestTimeout=62000 -Dapp.worker.capacity=60 -Dapp.worker.threads=10 -Dapp.worker.pollingDelay=1ms -Dapp.worker.completionDelay=50ms -Dapp.worker.workerName=worker -Dapp.worker.jobType=benchmark-task -Dapp.worker.payloadPath=bpmn/typical_payload.json -XX:+HeapDumpOnOutOfMemoryError" },
        { name = "LOG_LEVEL", value = "INFO" }
      ]
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
    }
  ])
}

# Worker service (internal only, 3 replicas)
resource "aws_ecs_service" "worker" {
  name            = "${var.prefix}-worker-service"
  cluster         = data.terraform_remote_state.stable.outputs["ecs_cluster_id"]
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 3

  force_new_deployment = var.force_new_deployment
  launch_type     = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets         = data.terraform_remote_state.stable.outputs["vpc_private_subnets"]
    security_groups = [
      data.terraform_remote_state.stable.outputs.security_groups_id["allow_camunda_ports"],
      data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_packages"],
    ]
    assign_public_ip = false
  }
}

