################################################################
#   Rebalancer - Region 0                                      #
################################################################
#
# Purpose
# -------
# Keeps partition leadership pinned to region 0 for the duration of a
# dual-region load test.
#
# The cluster uses ZONE_AWARE partitioning with region 0 at priority 1000 and
# region 1 at priority 500 (see locals.tf), so the *intent* is that every
# partition leader lives in region 0 and region 1 holds followers only. Raft
# priority election is best-effort though: any leader change (broker restart,
# ECS task replacement, a cross-region Raft hiccup, a failover experiment) can
# leave a partition led from region 1, and Zeebe does not move it back on its
# own. A leader in region 1 makes every command from the region-0 load
# generators pay an extra Transit Gateway round trip, which skews the
# throughput and latency numbers the load test is meant to measure.
#
# POSTing the broker management endpoint /actuator/rebalance asks the cluster to
# re-run priority election, handing leadership back to the highest-priority
# (region 0) replicas.
#
# Cadence
# -------
# Every 5 minutes. Rebalancing is a no-op when leadership already matches the
# priorities, so a short interval is cheap and bounds how long a load test can
# run with drifted leadership (worst case ~5 min of skewed measurements)
# without the churn of rebalancing continuously.
#
# The Lambda runs inside the region-0 VPC because the broker management port
# (9600) is only reachable via the private Cloud Map DNS record.
################################################################

locals {
  # Broker management endpoint (Service Discovery A record → broker IPs, port 9600).
  rebalance_url = "http://${module.orchestration_cluster_region_0.dns_a_record}:9600/actuator/rebalance"
}

data "archive_file" "rebalancer" {
  type        = "zip"
  output_path = "${path.module}/.build/rebalancer.zip"

  source {
    filename = "index.py"
    content  = <<-PY
      import os
      import urllib.request


      def handler(event, context):
          url = os.environ["REBALANCE_URL"]
          req = urllib.request.Request(url, method="POST")
          with urllib.request.urlopen(req, timeout=10) as resp:
              print(f"rebalance -> {resp.status}")
              return {"status": resp.status}
    PY
  }
}

resource "aws_iam_role" "rebalancer" {
  name = "${local.infra.cluster_name}-r0-rebalancer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# VPC access (ENI management) + CloudWatch Logs.
resource "aws_iam_role_policy_attachment" "rebalancer_vpc" {
  role       = aws_iam_role.rebalancer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "rebalancer" {
  function_name = "${local.infra.cluster_name}-r0-rebalancer"
  role          = aws_iam_role.rebalancer.arn
  runtime       = "python3.13"
  handler       = "index.handler"
  timeout       = 15

  filename         = data.archive_file.rebalancer.output_path
  source_code_hash = data.archive_file.rebalancer.output_base64sha256

  environment {
    variables = {
      REBALANCE_URL = local.rebalance_url
    }
  }

  vpc_config {
    subnet_ids         = local.infra.vpc_region_0_private_subnets
    security_group_ids = [local.infra.sg_camunda_ports_region_0_id]
  }
}

# IAM role assumed by EventBridge Scheduler to invoke the Lambda.
resource "aws_iam_role" "rebalancer_scheduler" {
  name = "${local.infra.cluster_name}-r0-rebalancer-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "rebalancer_scheduler" {
  name = "invoke"
  role = aws_iam_role.rebalancer_scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.rebalancer.arn
    }]
  })
}

resource "aws_scheduler_schedule" "rebalancer" {
  name = "${local.infra.cluster_name}-r0-rebalancer"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "rate(5 minutes)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.rebalancer.arn
    role_arn = aws_iam_role.rebalancer_scheduler.arn
  }
}
