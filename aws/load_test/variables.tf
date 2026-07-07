
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
  description = "When true, deploy load generators into the dual-region region-0 VPC/cluster (infra state dual-region/infra/<environment>.tfstate) instead of the single-region stable stack."
  default     = false
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
