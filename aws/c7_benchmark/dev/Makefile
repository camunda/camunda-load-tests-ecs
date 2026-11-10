ENV = dev
BENCHMARK_NUMBER ?= 1
# BENCHMARK_NAME (e.g. growing-1) overrides the numeric convention. Prefix max 20 chars.
ifdef BENCHMARK_NAME
  PREFIX = dev-$(BENCHMARK_NAME)
  BACKEND_KEY = dev/c7/$(BENCHMARK_NAME).tfstate
else
  PREFIX = dev-c7-$(BENCHMARK_NUMBER)
  BACKEND_KEY = dev/c7/c7-$(BENCHMARK_NUMBER).tfstate
endif
TFVARS_FILE = dev/terraform.tfvars
ECS_CLUSTER = camunda-dev-cluster
RESULTS_BUCKET ?= camunda-c7-benchmark-results-dev

include ../shared.mk
