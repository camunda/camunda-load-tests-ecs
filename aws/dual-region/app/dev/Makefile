ENV = dev
BENCHMARK_NAME ?= camunda-dr
CLUSTER_NAME = dev-$(BENCHMARK_NAME)
BACKEND_KEY = dual-region/app/$(CLUSTER_NAME).tfstate
TFVARS_FILE = dev/terraform.tfvars
EXTRA_TF_VARS = -var="infra_state_path=dual-region/infra/$(CLUSTER_NAME).tfstate"

include ../shared.mk
