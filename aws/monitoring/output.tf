output "alb_endpoint" {
  value       = join("", aws_lb.monitoring[*].dns_name)
  description = "(Optional) The DNS name of the Application Load Balancer (ALB) to access the Camunda Webapp."
}
