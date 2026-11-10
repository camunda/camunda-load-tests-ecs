output "engine_url" {
  value       = "http://${local.engine_host}:8080/engine-rest"
  description = "Engine REST API (inside the VPC)."
}

output "metrics_namespace" {
  value       = local.metrics_namespace
  description = "Prometheus `namespace` label of this run; select it in the C7 Benchmark dashboard."
}

output "aurora_cluster_id" {
  value = aws_rds_cluster.c7.cluster_identifier
}

output "aurora_endpoint" {
  value = aws_rds_cluster.c7.endpoint
}

output "results_task_definition" {
  value = aws_ecs_task_definition.results.arn
}

output "results_network" {
  value = {
    subnets         = local.stable.vpc_private_subnets
    security_groups = [aws_security_group.c7.id, local.stable.security_groups_id["allow_remote_packages"]]
  }
}
