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
  default     = "monitoring"
}

variable "gcp_federation_cidrs" {
  type        = list(string)
  description = "GCP CIDRs (node + pod ranges from infra-core cidrs.tf benchmark_gcp) that need inbound access to Prometheus on port 9001 over the Site-to-Site VPN"
  default     = []
}

