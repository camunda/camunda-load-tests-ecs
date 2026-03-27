
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  prometheus_port = data.terraform_remote_state.stable.outputs.ports.prometheus
}
# Prometheus task definition
resource "aws_ecs_task_definition" "prometheus" {
  family                   = "${var.prefix}-prometheus"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024

  container_definitions = jsonencode([
    {
      name      = "discovery"
      image     = "amazon/aws-cli:latest"
      essential = true
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "cat <<'SCRIPT' > /tmp/discover.sh\n${file("${path.module}/templates/discover-targets.sh")}\nSCRIPT\nchmod +x /tmp/discover.sh && exec /tmp/discover.sh"
      ]
      environment = [
        { name = "TARGETS_FILE", value = "/etc/prometheus/targets/benchmarks.json" },
        { name = "REFRESH_INTERVAL", value = "30" },
        { name = "PORT", value = "9600" },
        { name = "AWS_DEFAULT_REGION", value = data.aws_region.current.name },
        { name = "ENVIRONMENT", value = var.environment }
      ]
      mountPoints = [
        {
          sourceVolume  = "targets"
          containerPath = "/etc/prometheus/targets"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.monitoring_log_group.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "discovery"
        }
      }
    },
    {
      name      = "prometheus"
      image     = "registry.camunda.cloud/team-zeebe/prometheus:v3.7.3"
      repositorycredentials: {
        credentialsparameter: data.terraform_remote_state.stable.outputs.registry_credentials_arn
      },
      essential = true
      dependsOn = [
        { containerName = "discovery", condition = "START" }
      ]
      portMappings = [
        { containerPort = local.prometheus_port, hostPort = local.prometheus_port, protocol = "tcp" }
      ]
      entryPoint = ["/bin/sh", "-c"]
      command = [
        "cat <<'EOF' >/etc/prometheus/prometheus.yml\n${templatefile("${path.module}/templates/prometheus-config.yml.tpl", { prefix = var.prefix }) }\nEOF\nexec /bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.retention.time=168h --web.enable-lifecycle --web.listen-address=:${data.terraform_remote_state.stable.outputs.ports.prometheus}"
      ]
      mountPoints = [
        {
          sourceVolume  = "targets"
          containerPath = "/etc/prometheus/targets"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.monitoring_log_group.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "prometheus"
        }
      }
    }
  ])

  volume {
    name = "targets"
  }
}
# Prometheus service (internal only)
resource "aws_ecs_service" "prometheus" {
  # depends_on = [aws_lb_target_group.prometheus_9090]
  name            = "${var.prefix}-prometheus"
  cluster         = data.terraform_remote_state.stable.outputs.ecs_cluster_id
  task_definition = aws_ecs_task_definition.prometheus.arn
  desired_count   = 1
  force_new_deployment = true
  launch_type     = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets         = data.terraform_remote_state.stable.outputs.vpc_private_subnets
    security_groups = concat(
      [
        data.terraform_remote_state.stable.outputs.security_groups_id["allow_camunda_ports"],
        data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_packages"],
      ],
      aws_security_group.allow_gcp_prometheus_federation[*].id,
    )
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.prometheus.arn
  }
}

