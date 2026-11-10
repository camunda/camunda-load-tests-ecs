data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: pull images (registry.camunda.cloud credentials), read the DB password, write logs.
resource "aws_iam_role" "execution" {
  name               = "${var.prefix}-c7-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "execution_registry" {
  role       = aws_iam_role.execution.name
  policy_arn = local.stable.registry_credentials_iam_policy
}

resource "aws_iam_role_policy" "execution_db_secret" {
  name = "${var.prefix}-c7-db-secret"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.db_password.arn]
    }]
  })
}

# Task role: ECS exec for debugging; results task reads CloudWatch and writes to the results bucket.
resource "aws_iam_role" "task" {
  name               = "${var.prefix}-c7-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "task" {
  name = "${var.prefix}-c7-task"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel",
          ]
          Resource = "*"
        },
        {
          Effect   = "Allow"
          Action   = ["cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "pi:GetResourceMetrics"]
          Resource = "*"
        },
      ],
      var.results_bucket == "" ? [] : [{
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["arn:aws:s3:::${var.results_bucket}/*"]
      }]
    )
  })
}
