resource "aws_cloudwatch_log_group" "monitoring_log_group" {
  name              = "/ecs/${var.prefix}"
  retention_in_days = 1

  tags = {
    Name = "${var.prefix}-log-group"
  }
}
