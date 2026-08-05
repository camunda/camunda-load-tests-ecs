ENV = dev
BENCHMARK_NAME ?= camunda-dr
DATABASE_ENGINE ?= postgresql
CLUSTER_NAME = dev-$(BENCHMARK_NAME)
BACKEND_KEY = dual-region/infra/$(CLUSTER_NAME).tfstate
TFVARS_FILE = dev/terraform.tfvars
EXTRA_TF_VARS = -var="cluster_name=$(CLUSTER_NAME)" \
	-var="database_engine=$(DATABASE_ENGINE)" \
	-var="vpc_state_path=dual-region/vpc/$(CLUSTER_NAME).tfstate" \
	-var="stable_environment=$(ENV)"

include ../shared.mk
