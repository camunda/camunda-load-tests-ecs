
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_private_subnets" {
  description = "The private subnets of the VPC"
  value       = module.vpc.private_subnets
}

output "vpc_public_subnets" {
  description = "The private subnets of the VPC"
  value       = module.vpc.public_subnets
}
output "ecs_cluster_id" {
  description = "The ID of the ECS Cluster"
  value       = aws_ecs_cluster.ecs.id
}

output "registry_credentials_arn" {
  description = "The ARN of the registry credentials secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret.registry_credentials.arn
}

output "registry_credentials_iam_policy" {
  description = "The IAM policy ARN for accessing the registry credentials"
  value       = aws_iam_policy.registry_secrets_policy.arn
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository for Camunda images"
  value       = aws_ecr_repository.camunda.repository_url
}

output "ecr_repository_arn" {
  description = "The ARN of the ECR repository for Camunda images"
  value       = aws_ecr_repository.camunda.arn
}

output "security_groups_id" {
  description = "The IDs of the created security groups"
  value = {
    allow_camunda_ports   = aws_security_group.allow_necessary_camunda_ports_within_vpc.id
    allow_remote_packages = aws_security_group.allow_package_80_443.id
    allow_efs             = aws_security_group.efs.id
    allow_remote_80_443   = aws_security_group.allow_remote_80_443.id
    allow_remote_9600     = aws_security_group.allow_remote_9600.id
    allow_remote_grpc     = aws_security_group.allow_remote_grpc.id
    allow_remote_3000     = aws_security_group.allow_remote_3000.id
  }
}

output "ports" {
  description = "The ports configuration for services"
  value       = var.ports
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}
