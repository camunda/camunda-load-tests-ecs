output "alb_endpoint" {
  value       = join("", aws_lb.monitoring[*].dns_name)
  description = "(Optional) The DNS name of the Application Load Balancer (ALB) to access the Camunda Webapp."
}

output "prometheus_nlb_dns" {
  value       = var.expose_via_internal_nlb ? aws_lb.prometheus_internal[0].dns_name : null
  description = "DNS name of the internal NLB fronting Prometheus, for cross-region federation (null unless expose_via_internal_nlb = true)"
}
