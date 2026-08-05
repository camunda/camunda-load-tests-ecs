
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

################################################################
#                        Global Options                        #
################################################################

variable "environment" {
  type        = string
  description = "Environment name (dev or prod)"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be 'dev' or 'prod'."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy the load test resources into. Backend and source remote-state stay in eu-west-1."
  default     = "eu-west-1"
}

variable "prefix" {
  type        = string
  description = "The prefix to use for names of resources"
  default     = "load_test1"
}

variable "camunda_host" {
  type    = string
  default = "orchestration-cluster.benchmark1-oc.service.local"
}

variable "dual_region" {
  type        = bool
  description = "When true, deploy load generators into the dual-region region-0 VPC/cluster (infra state dual-region/infra/<environment>-camunda-dr.tfstate) instead of the single-region stable stack."
  default     = false
}

variable "dual_region_index" {
  type        = number
  default     = 0
  description = "Which dual-region region to deploy load generators into: 0 (region_0, default) or 1 (region_1). Ignored unless dual_region=true. Provider region is derived from the dual-region infra state for the chosen region."

  validation {
    condition     = contains([0, 1], var.dual_region_index)
    error_message = "dual_region_index must be 0 or 1."
  }
}

variable "dual_region_infra_state_key" {
  type        = string
  default     = ""
  description = "Explicit S3 key of the dual-region infra state to read (rotating name). Empty derives dual-region/infra/<environment>-camunda-dr.tfstate (matches dual-region/infra's default BENCHMARK_NAME=camunda-dr)."
}

variable "grpc_address" {
  type        = string
  description = "Full gRPC client address (e.g. http://<lb-dns>:26500). Empty derives http://<camunda_host>:26500 from Cloud Map."
  default     = ""
}

variable "rest_address" {
  type        = string
  description = "Full REST client address (e.g. http://<lb-dns>:80). Empty derives http://<camunda_host>:8080 from Cloud Map."
  default     = ""
}

variable "prefer_rest_over_grpc" {
  type        = string
  description = "When true, starter and worker use REST instead of gRPC for the Camunda client."
  default     = "false"
}

variable "starter_image" {
  type        = string
  description = "Docker image for the starter (load generator)"
  default     = "registry.camunda.cloud/team-zeebe/starter:SNAPSHOT"
}

variable "worker_image" {
  type        = string
  description = "Docker image for the worker (job worker)"
  default     = "registry.camunda.cloud/team-zeebe/worker:SNAPSHOT"
}

variable "camunda_image" {
  type        = string
  description = "The Docker image to use for Camunda"
  default     = "camunda/camunda:SNAPSHOT"
}

variable "registry_username" {
  type        = string
  description = "Registry username for private image access"
  default     = ""
  sensitive   = true
}

variable "registry_password" {
  type        = string
  description = "Registry password for private image access"
  default     = ""
  sensitive   = true
}

variable "camunda_auth_username" {
  type        = string
  description = "Basic-auth username for the Camunda client. Empty disables basic auth (cluster must have an unprotected API)."
  default     = ""
}

variable "camunda_auth_password_secret_arn" {
  type        = string
  description = "Secrets Manager ARN holding the basic-auth password. Required when camunda_auth_username is set."
  default     = ""
}

variable "camunda_auth_password_kms_key_arn" {
  type        = string
  description = "KMS key ARN encrypting the basic-auth password secret. Set when the secret uses a customer-managed key (e.g. the dual-region secrets CMK) so the execution role can decrypt it."
  default     = ""
}

variable "force_new_deployment" {
  type        = bool
  description = "Whether to force redeployment of resources"
  default     = false
}

variable "load_test_duration" {
  type        = string
  description = "How long the load-test services should run before ECS scales them to zero (Go duration, e.g. 6h or 30m)."
  default     = "6h"

  validation {
    condition     = can(timeadd("2000-01-01T00:00:00Z", var.load_test_duration))
    error_message = "load_test_duration must be a valid Go-style duration accepted by Terraform timeadd, such as 6h or 30m."
  }
}
