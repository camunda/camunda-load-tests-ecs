# One-off task that turns a finished run into a results folder (see results/collect.sh).
# Runs inside the VPC so it reaches Prometheus via Cloud Map. Started by `make results`.

resource "aws_ecs_task_definition" "results" {
  family                   = "${var.prefix}-c7-results"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name                  = "results"
    image                 = var.results_image
    repositoryCredentials = local.registry_credentials
    essential             = true
    environment = [
      { name = "PROMETHEUS_URL", value = var.prometheus_url },
      { name = "METRICS_NAMESPACE", value = local.metrics_namespace },
      { name = "RESULTS_BUCKET", value = var.results_bucket },
      { name = "AURORA_CLUSTER_ID", value = aws_rds_cluster.c7.cluster_identifier },
      { name = "AURORA_INSTANCE_ID", value = aws_rds_cluster_instance.c7.identifier },
      # Recorded in metadata.json so a result can be traced to its configuration.
      { name = "RUN_CONFIG", value = jsonencode({
        environment       = var.environment
        prefix            = var.prefix
        engine_image      = var.engine_image
        load_tester_image = var.load_tester_image
        engine_count      = var.engine_count
        engine_cpu        = var.engine_cpu
        engine_memory     = var.engine_memory
        history_level     = var.history_level
        history_cleanup   = var.history_cleanup
        starter_rate      = var.starter_rate
        payload           = var.starter_payload_path
        worker_count      = var.worker_count
        worker_capacity   = var.worker_capacity
        worker_delay      = var.worker_completion_delay
        aurora_class      = var.aurora_instance_class
        aurora_version    = var.aurora_engine_version
        aurora_storage    = var.aurora_storage_type
      }) },
    ]
    logConfiguration = local.log_config
  }])
}
