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

variable "region" {
  type        = string
  default     = "eu-west-1"
  description = "AWS region to deploy this monitoring stack into. Used for the dual-region secondary (us-east-1) instance; single-region tests keep the default."
}

variable "stable_state_key" {
  type        = string
  default     = ""
  description = "Override for the aws/stable S3 state key this monitoring stack reads (VPC, ECS cluster, SGs). Empty (default) derives it from var.environment; set explicitly for stacks whose stable state doesn't follow the dev/prod naming, e.g. the dual-region secondary in us-east-1."
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

variable "federation_source_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to scrape this Prometheus's /federate endpoint over VPC peering (dual-region: the paired region's VPC CIDR)"
  default     = []
}

variable "federation_target_cidrs" {
  type        = list(string)
  description = "CIDRs this Prometheus needs to reach on :9001 to scrape a remote /federate endpoint over VPC peering (dual-region: the paired region's VPC CIDR)"
  default     = []
}

variable "expose_via_internal_nlb" {
  type        = bool
  default     = false
  description = "Front the Prometheus ECS service with an internal NLB so it has a static DNS name reachable cross-region over VPC peering. Set true on the dual-region secondary (region_1) monitoring instance; the primary federates it via this NLB's DNS name."
}

variable "federation_peer_monitoring_state_key" {
  type        = string
  default     = ""
  description = "S3 key (bucket zeebe-terraform-states) of the paired region's aws/monitoring state, used to federate its Prometheus /federate endpoint. Set on the primary (region_0) instance to the secondary's state key; leave empty on the secondary and on single-region deployments."
}

