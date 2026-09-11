################################
# Region Configuration        #
################################

variable "region_0" {
  type        = string
  default     = "eu-west-2"
  description = "AWS region for the primary (owner) cluster"
}

variable "region_1" {
  type        = string
  default     = "eu-west-3"
  description = "AWS region for the secondary (accepter) cluster"
}

################################################################
#                       VPC State Reference                     #
################################################################

variable "vpc_state_path" {
  type        = string
  default     = "dual-region/vpc/dev.tfstate"
  description = "S3 key of the vpc/ terraform state (bucket zeebe-terraform-states). infra/ reads VPC IDs, subnet IDs, CIDRs, etc. from this state."
}

################################################################
#                   Secondary Storage Options                   #
################################################################

variable "secondary_storage_type" {
  type        = string
  default     = "rdbms"
  description = "Camunda secondary storage: 'rdbms' (Aurora Global) or 'opensearch'"

  validation {
    condition     = contains(["rdbms", "opensearch"], var.secondary_storage_type)
    error_message = "Must be 'rdbms' or 'opensearch'."
  }
}

variable "database_engine" {
  type        = string
  default     = "postgresql"
  description = "Aurora Global database engine: 'postgresql' or 'mysql'"

  validation {
    condition     = contains(["postgresql", "mysql"], var.database_engine)
    error_message = "Must be 'postgresql' or 'mysql'."
  }
}

################################
# Variables                    #
################################

variable "cluster_name" {
  type        = string
  description = "Name of the cluster to prefix resources"
}

variable "stable_environment" {
  type        = string
  default     = "dev"
  description = "Environment name of the stable stack (stable/<env>/terraform.tfstate) whose registry credentials to reuse for region 0"
}

variable "aws_profile" {
  type        = string
  description = "AWS Profile to use (null = use default credential chain)"
  default     = null
}

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all resources"
}

################################################################
#                       Security Options                        #
################################################################

variable "limit_access_to_cidrs" {
  type        = list(string)
  default     = []
  description = "Extra CIDR blocks to allow access to the LoadBalancers, on top of each region's own VPC CIDR (which is always allowed and is derived from the vpc/ state). Leave empty to keep both regions reachable only from inside their own VPC; set e.g. [\"0.0.0.0/0\"] to expose them publicly."
}

variable "ports" {
  type = map(number)
  default = {
    mysql                                 = 3306
    postgresql                            = 5432
    camunda_web_ui                        = 8080
    camunda_metrics_endpoint              = 9600
    zeebe_gateway_cluster_port            = 26502
    zeebe_gateway_network_port            = 26500
    zeebe_broker_network_command_api_port = 26501
  }
  description = "The ports to open for the security groups within the VPC. Both database ports are listed (mysql 3306, postgresql 5432); Aurora itself only listens on the one matching var.database_engine"
}

################################################################
#                     Database Options                          #
################################################################

variable "db_name" {
  type        = string
  description = "Database name used by Camunda components"
  default     = "camunda"
}

variable "db_admin_username" {
  type        = string
  description = "Admin username for the Aurora Global cluster (engine per var.database_engine)"
  default     = "camunda_admin"
  sensitive   = true
}

variable "db_admin_password" {
  type        = string
  description = "Optional override for the Aurora Global cluster admin password. If empty, a random password is generated."
  default     = ""
  sensitive   = true
}

variable "db_iam_auth_enabled" {
  type        = bool
  description = "Enable IAM database authentication on the Aurora cluster"
  default     = true
}

variable "db_seed_enabled" {
  type        = bool
  description = "Run a one-time ECS task to create/grant IAM DB users"
  default     = true
}

variable "db_seed_iam_usernames" {
  type        = list(string)
  description = "Database users to create and grant rds_iam + privileges for"
  default     = ["camunda"]
}

variable "db_seed_run_id" {
  type        = string
  description = "Increment this value to force the DB seed task to re-run on the next apply (e.g. '1' → '2'). All SQL is idempotent so re-running is safe."
  default     = "1"
}

################################################################
#                      S3 Options                               #
################################################################

variable "s3_force_destroy" {
  type        = bool
  default     = true
  description = "Allow Terraform to destroy S3 backup buckets even if they contain objects. Defaults to true because this is a reference / demo architecture and `terraform destroy` should clean up without manual S3 cleanup. Set to false before running a real workload through it so Terraform refuses to drop backup data."
}

################################################################
#                     Registry Options                          #
################################################################

variable "registry_username" {
  type        = string
  description = "(Optional) The username for the container registry"
  default     = ""
}

variable "registry_password" {
  type        = string
  description = "(Optional) The password for the container registry"
  default     = ""
}

################################################################
#                         KMS Options                          #
################################################################

variable "secrets_kms_key_arn" {
  description = "Optional existing KMS key ARN for region 0. If empty, a CMK is created."
  type        = string
  default     = ""
}

variable "secrets_kms_key_arn_accepter" {
  description = "Optional existing KMS key ARN for region 1. If empty, a CMK is created."
  type        = string
  default     = ""
}
