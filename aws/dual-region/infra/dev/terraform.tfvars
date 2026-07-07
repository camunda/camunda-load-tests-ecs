region_0               = "eu-west-1"
region_1               = "us-east-1"
secondary_storage_type = "rdbms"

# Restrict LoadBalancer ingress to the stable load-test VPC (region_0 CIDR),
# where the in-VPC starter/worker run. The cluster must not be reachable from
# the public internet. Default is 0.0.0.0/0 — do not use it here.
limit_access_to_cidrs = ["10.52.0.0/16"]
