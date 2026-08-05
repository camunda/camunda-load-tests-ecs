# Stop the load-test services automatically so a forgotten run cannot keep
# consuming ECS capacity indefinitely. The timestamp is persisted in Terraform
# state and is reset when the load-test prefix changes.
resource "time_static" "load_test_started_at" {
  triggers = {
    prefix = var.prefix
  }
}

resource "aws_iam_role" "auto_stop_scheduler" {
  name = "${var.prefix}-auto-stop-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "auto_stop_scheduler" {
  name = "${var.prefix}-auto-stop-scheduler"
  role = aws_iam_role.auto_stop_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ecs:UpdateService"
      Resource = "*"
    }]
  })
}

locals {
  auto_stop_at = formatdate(
    "YYYY-MM-DD'T'hh:mm:ss'Z'",
    timeadd(time_static.load_test_started_at.rfc3339, var.load_test_duration)
  )
  scheduler_target_arn = "arn:aws:scheduler:::aws-sdk:ecs:updateService"
}

resource "aws_scheduler_schedule" "stop_starter" {
  name                         = "${var.prefix}-stop-starter"
  schedule_expression          = "at(${local.auto_stop_at})"
  schedule_expression_timezone = "UTC"
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = local.scheduler_target_arn
    role_arn = aws_iam_role.auto_stop_scheduler.arn
    input = jsonencode({
      Cluster      = local.ecs_cluster_id
      Service      = aws_ecs_service.starter.name
      DesiredCount = 0
    })
  }
}

resource "aws_scheduler_schedule" "stop_worker" {
  name                         = "${var.prefix}-stop-worker"
  schedule_expression          = "at(${local.auto_stop_at})"
  schedule_expression_timezone = "UTC"
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = local.scheduler_target_arn
    role_arn = aws_iam_role.auto_stop_scheduler.arn
    input = jsonencode({
      Cluster      = local.ecs_cluster_id
      Service      = aws_ecs_service.worker.name
      DesiredCount = 0
    })
  }
}
