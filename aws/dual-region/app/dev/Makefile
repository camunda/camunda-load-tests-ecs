ENV = dev
BENCHMARK_NAME ?= camunda-dr
CLUSTER_NAME = dev-$(BENCHMARK_NAME)
BACKEND_KEY = dual-region/app/$(CLUSTER_NAME).tfstate
TFVARS_FILE = dev/terraform.tfvars
STATE_DESC = Dual-Region Camunda App (Zeebe brokers, gateway, connectors)
# Optional Camunda image override (empty = keep the SNAPSHOT default in variables.tf).
CAMUNDA_IMAGE ?=
EXTRA_TF_VARS = -var="infra_state_path=dual-region/infra/$(CLUSTER_NAME).tfstate"$(if $(CAMUNDA_IMAGE), -var="camunda_image=$(CAMUNDA_IMAGE)")

include ../../shared.mk
