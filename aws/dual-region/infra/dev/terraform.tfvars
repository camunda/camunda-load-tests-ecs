region_0               = "eu-west-1"
region_1               = "us-east-1"
secondary_storage_type = "rdbms"

# stable/<env>/terraform.tfstate whose registry credentials region 0 reuses.
stable_environment = "dev"

# LoadBalancer ingress is restricted to each region's own VPC CIDR (derived from
# the vpc/ state: 10.52.0.0/16 in eu-west-1, 10.60.0.0/16 in us-east-1), where the
# in-VPC starter/worker run. The cluster must not be reachable from the public
# internet, so leave limit_access_to_cidrs empty — anything listed here is opened
# on *both* regions' load balancers.
limit_access_to_cidrs = []
