ENV = dev
BENCHMARK_NUMBER ?= 1
# Allow overriding PREFIX directly via BENCHMARK_NAME (e.g., weekly-2026-03-17)
# Falls back to the numeric convention (dev-benchmark1) when BENCHMARK_NAME is not set
ifdef BENCHMARK_NAME
  PREFIX = dev-$(BENCHMARK_NAME)
  BACKEND_KEY = dev/benchmarks/$(BENCHMARK_NAME).tfstate
else
  PREFIX = dev-benchmark$(BENCHMARK_NUMBER)
  BACKEND_KEY = dev/benchmarks/benchmark$(BENCHMARK_NUMBER).tfstate
endif
TFVARS_FILE = dev/terraform.tfvars
ECS_CLUSTER = camunda-dev-cluster

include ../shared.mk
