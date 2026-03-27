resource "aws_service_discovery_private_dns_namespace" "namespace" {
  name        = "${var.prefix}.service.local"
  vpc         = data.terraform_remote_state.stable.outputs.vpc_id
  description = "Namespace for ECS services"
}

resource "aws_service_discovery_service" "prometheus" {
  name = "prometheus"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.namespace.id
    dns_records {
      type = "A"
      ttl  = 10
    }
    routing_policy = "MULTIVALUE"
  }
}

