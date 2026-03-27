
# Load Balancer

resource "aws_lb_target_group" "grafana_3000" {
  name        = "${var.prefix}-tg-grafana-3000"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.stable.outputs.vpc_id
  target_type = "ip"

  deregistration_delay = 30

  health_check {
    path                = "/api/health"
    port                = "3000"
    protocol            = "HTTP"
    timeout             = 5
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http_3000" {

  load_balancer_arn = aws_lb.monitoring.arn
  port              = "80" # so you don't have to specify the port in the URL
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana_3000.arn
  }
}

# ECS

resource "aws_ecs_task_definition" "grafana" {
  family                   = "${var.prefix}-grafana"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024

  container_definitions = jsonencode([
    {
      name      = "grafana"
      image     = "registry.camunda.cloud/team-zeebe/grafana:12.3"
      repositorycredentials: {
        credentialsparameter: data.terraform_remote_state.stable.outputs.registry_credentials_arn
      },
      essential = true
      portMappings = [
        { containerPort = 3000, hostPort = 3000, protocol = "tcp" }
      ]
      environment = [
        # { name = "GF_SECURITY_ADMIN_USER", value = var.grafana_user },
        # { name = "GF_SECURITY_ADMIN_PASSWORD", value = var.grafana_pass },
        { name = "GF_INSTALL_PLUGINS", value = "grafana-piechart-panel" },
        { name = "GF_FEATURE_TOGGLES_ENABLE", value = "publicDashboards" },
        { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "true" },
        { name = "GF_AUTH_ANONYMOUS_ORG_ROLE", value = "Admin" }
      ]
      entryPoint = ["/bin/sh", "-c"]
      command = ["cat <<'EOF' >/etc/grafana/provisioning/datasources/prometheus.yml\napiVersion: 1\ndatasources:\n  - name: Prometheus\n    type: prometheus\n    url: http://prometheus.${var.prefix}.service.local:9001\n    access: proxy\n    isDefault: true\n    editable: true\n    jsonData:\n      httpMethod: GET\nEOF\nmkdir -p /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards && cat <<'YAML' >/etc/grafana/provisioning/dashboards/zeebe.yaml\napiVersion: 1\nproviders:\n  - name: 'zeebe'\n    orgId: 1\n    folder: ''\n    type: file\n    disableDeletion: true\n    editable: false\n    options:\n      path: /var/lib/grafana/dashboards\nYAML\ncurl -Ls https://raw.githubusercontent.com/camunda/camunda/main/monitor/grafana/zeebe.json -o /var/lib/grafana/dashboards/zeebe.json || echo 'failed to fetch dashboard';\nexec /run.sh"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.monitoring_log_group.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "grafana"
        }
      }
    }
  ])
}

# Grafana service (exposed via ALB 80)
resource "aws_ecs_service" "grafana" {
  depends_on = [aws_ecs_service.prometheus]
  name            = "${var.prefix}-grafana-service"
  cluster         = data.terraform_remote_state.stable.outputs.ecs_cluster_id
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = 1
  force_new_deployment = true
  launch_type     = "FARGATE"
  enable_execute_command = true
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets         = data.terraform_remote_state.stable.outputs.vpc_private_subnets
    security_groups = [
      data.terraform_remote_state.stable.outputs.security_groups_id["allow_camunda_ports"],
      data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_packages"],
    ]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana_3000.arn
    container_name   = "grafana"
    container_port   = 3000
  }
}
