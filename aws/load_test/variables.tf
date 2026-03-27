
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

variable "camunda_host"{
  type = string
  default =     "orchestration-cluster.benchmark1-oc.service.local"
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

variable "force_new_deployment" {
  type        = bool
  description = "Whether to force redeployment of resources"
  default     = false
}