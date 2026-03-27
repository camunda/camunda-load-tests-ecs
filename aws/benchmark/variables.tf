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
  default     = "benchmark1"
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
