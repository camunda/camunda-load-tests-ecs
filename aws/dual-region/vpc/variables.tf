################################################################
#                       BYO-VPC Toggle                          #
################################################################

variable "byo_vpc" {
  type        = bool
  default     = false
  description = <<-EOT
    If true, this state consumes the existing aws/stable VPCs (region_0 from
    stable_region_0_state_key, region_1 from stable_region_1_state_key) and
    only creates cross-region peering/TGW plus optional Route 53 Resolver
    endpoints. If false (default), Terraform creates two VPCs from scratch
    using terraform-aws-modules/vpc/aws.
  EOT
}

################################################################
#                  Region & Naming Variables                    #
################################################################

variable "cluster_name" {
  type        = string
  description = "Name of the cluster to prefix resources (used for created resources only — BYO resources keep their existing names)"
}

variable "aws_profile" {
  type        = string
  description = "AWS Profile to use (null = use default credential chain)"
  default     = null
}

variable "default_tags" {
  type        = map(string)
  default     = {}
  description = "Default tags to apply to all created resources"
}

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
#                  Greenfield VPC Inputs                        #
#  (used only when byo_vpc = false)                             #
################################################################

variable "region_0_cidr" {
  type        = string
  default     = "10.192.0.0/16"
  description = "VPC CIDR block to create for region 0 (only used when byo_vpc = false)"

  validation {
    condition     = can(cidrnetmask(var.region_0_cidr))
    error_message = "region_0_cidr must be a valid CIDR block."
  }
}

variable "region_1_cidr" {
  type        = string
  default     = "10.202.0.0/16"
  description = "VPC CIDR block to create for region 1 (only used when byo_vpc = false)"

  validation {
    condition     = can(cidrnetmask(var.region_1_cidr))
    error_message = "region_1_cidr must be a valid CIDR block."
  }
}

variable "single_nat_gateway" {
  type        = bool
  default     = false
  description = "If true, only one NAT gateway will be created per region to save on e.g. IPs, not good for HA. Only used when byo_vpc = false."
}

################################################################
#                       BYO-VPC Inputs                          #
#  (used only when byo_vpc = true)                               #
################################################################

variable "stable_region_0_state_key" {
  type        = string
  default     = "stable/prod/terraform.tfstate"
  description = "S3 key (bucket zeebe-terraform-states) of the aws/stable state to source region_0's VPC from. Required when byo_vpc = true."
}

variable "stable_region_1_state_key" {
  type        = string
  default     = "stable/us-east-1/terraform.tfstate"
  description = "S3 key (bucket zeebe-terraform-states) of the aws/stable state to source region_1's VPC from. Required when byo_vpc = true."
}

################################################################
#                    Networking Options                         #
################################################################

variable "networking_mode" {
  type        = string
  default     = "vpc_peering"
  description = "Cross-region networking: 'vpc_peering' (default — simpler, no per-attachment hourly fee, fits two regions) or 'transit_gateway' (hub-and-spoke, needed when extending the topology beyond two VPCs)."

  validation {
    condition     = contains(["transit_gateway", "vpc_peering"], var.networking_mode)
    error_message = "Must be 'transit_gateway' or 'vpc_peering'."
  }
}

################################################################
#                      DNS Options                              #
################################################################

variable "enable_cross_region_dns_resolver" {
  type        = bool
  default     = false
  description = <<-EOT
    Create Route 53 Resolver endpoints and forwarding rules for cross-region Cloud Map DNS.
    Requires the IAM permission route53resolver:CreateResolverEndpoint on the calling principal.
    Zeebe Raft and Connectors work without this because cross-region contact uses NLB DNS names.
    Enable once the permission is granted if you need cross-region Service Connect name resolution.
  EOT
}
