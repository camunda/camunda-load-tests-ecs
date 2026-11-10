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
  description = "Resource name prefix, e.g. dev-c7-1. Max 20 characters (target group and RDS name limits)."
  validation {
    condition     = length(var.prefix) <= 20
    error_message = "prefix must be at most 20 characters."
  }
}

variable "force_new_deployment" {
  type    = bool
  default = false
}

################################################################
#                           Images                             #
################################################################

variable "engine_image" {
  type    = string
  default = "registry.camunda.cloud/team-zeebe/c7-benchmark-engine:7.24.0-SNAPSHOT"
}

variable "load_tester_image" {
  type    = string
  default = "registry.camunda.cloud/team-zeebe/c7-benchmark-load-tester:7.24.0-SNAPSHOT"
}

variable "postgres_exporter_image" {
  type    = string
  default = "quay.io/prometheuscommunity/postgres-exporter:v0.17.1"
}

################################################################
#                           Engine                             #
################################################################

variable "engine_count" {
  type        = number
  description = "Engines sharing the database. 1 = single node. 3 = same compute as the C8 OC benchmark (3 x 4 vCPU)."
  default     = 1
}

variable "engine_cpu" {
  type        = number
  description = "Fargate CPU units per engine. Same as the C8 orchestration-cluster task (4096)."
  default     = 4096
}

variable "engine_memory" {
  type    = number
  default = 8192
}

variable "engine_db_pool_size" {
  type    = number
  default = 30
}

variable "history_level" {
  type    = string
  default = "full"
}

variable "history_cleanup" {
  type        = bool
  description = "false = growing state (history is never removed)."
  default     = false
}

variable "cockpit_enabled" {
  type    = bool
  default = false
}

################################################################
#                          Load test                           #
################################################################

variable "starter_rate" {
  type        = number
  description = "Process instances per second. C8 ECS benchmark uses 150."
  default     = 150
}

variable "starter_payload_path" {
  type    = string
  default = "payload/typical_payload.json"
}

variable "starter_duration_limit" {
  type        = number
  description = "Seconds after which the starter stops; 0 = run until destroyed."
  default     = 0
}

variable "worker_count" {
  type    = number
  default = 3
}

variable "worker_capacity" {
  type    = number
  default = 60
}

variable "worker_threads" {
  type    = number
  default = 10
}

variable "worker_completion_delay" {
  type    = string
  default = "50ms"
}

################################################################
#                           Aurora                             #
################################################################

variable "aurora_instance_class" {
  type        = string
  description = "Use a non-burstable class (r7g/r8g). db.t3/t4g run on CPU credits and distort results."
  default     = "db.r7g.large"
}

variable "aurora_engine_version" {
  type    = string
  default = "17.7"
}

variable "aurora_storage_type" {
  type        = string
  description = "aurora-iopt1 (I/O-Optimized, no per-I/O charges) or aurora (Standard)."
  default     = "aurora-iopt1"
}

################################################################
#                           Results                            #
################################################################

variable "results_bucket" {
  type        = string
  description = "S3 bucket for run results (created by aws/c7_results). Empty disables the upload permission."
  default     = ""
}

variable "results_image" {
  type    = string
  default = "registry.camunda.cloud/team-zeebe/c7-benchmark-results:latest"
}

variable "prometheus_url" {
  type        = string
  description = "Prometheus of the shared monitoring layer, reachable inside the VPC."
  default     = "http://prometheus.dev-monitoring.service.local:9090"
}
