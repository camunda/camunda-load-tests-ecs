ENV = dev
# Rotating run name. Default reproduces the original single-run stack.
BENCHMARK_NAME ?= camunda-dr
CLUSTER_NAME = dev-$(BENCHMARK_NAME)
BACKEND_KEY = dual-region/vpc/$(CLUSTER_NAME).tfstate
TFVARS_FILE = dev/terraform.tfvars
STATE_DESC = Dual-Region VPC
EXTRA_TF_VARS = -var="cluster_name=$(CLUSTER_NAME)"

include ../../shared.mk
