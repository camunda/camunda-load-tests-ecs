################################################################
#                        Global Options                        #
################################################################

variable "prefix" {
  type        = string
  description = "The prefix to use for names of resources"
  default     = "camunda"
}

################################################################
#                       Network Options                        #
################################################################

variable "cidr_blocks" {
  type        = string
  default     = "10.52.0.0/16"
  description = "The CIDR block to use for the VPC. Dev: 10.52.0.0/16, Prod: 10.50.0.0/16 (10.51.0.0/16 reserved for stage)"
}

################################################################
#                      Security Options                        #
################################################################

variable "limit_access_to_cidrs" {
  type        = list(string)
  default     = ["3.125.83.158/32"] # limit to Camunda VPN
  description = "List of CIDR blocks to allow access to ssh of Bastion and LoadBalancer"
}

variable "ports" {
  type = map(number)
  default = {
    camunda_web_ui                        = 8080
    camunda_metrics_endpoint              = 9600
    connectors_port                       = 9090
    zeebe_gateway_cluster_port            = 26502
    zeebe_gateway_network_port            = 26500
    zeebe_broker_network_command_api_port = 26501
    grafana                               = 3000
    prometheus                            = 9001
  }
  description = "The ports to open for the security groups within the VPC"
}
