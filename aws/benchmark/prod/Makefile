ENV = prod
BENCHMARK_NUMBER ?= 1
# Allow overriding PREFIX directly via BENCHMARK_NAME (e.g., weekly-2026-03-17)
# Falls back to the numeric convention (benchmark1) when BENCHMARK_NAME is not set
ifdef BENCHMARK_NAME
  PREFIX = $(BENCHMARK_NAME)
  BACKEND_KEY = benchmarks/$(BENCHMARK_NAME).tfstate
else
  PREFIX = benchmark$(BENCHMARK_NUMBER)
  BACKEND_KEY = benchmarks/benchmark$(BENCHMARK_NUMBER).tfstate
endif
TFVARS_FILE = prod/terraform.tfvars
ECS_CLUSTER = camunda-cluster

include ../shared.mk
