ENV = prod
BENCHMARK_NUMBER ?= 1
# Allow overriding PREFIX directly via BENCHMARK_NAME (e.g., weekly-2026-03-17)
# Falls back to the numeric convention (load_test1) when BENCHMARK_NAME is not set
ifdef BENCHMARK_NAME
  PREFIX = $(BENCHMARK_NAME)-lt
  BACKEND_KEY = load_tests/$(BENCHMARK_NAME)-lt.tfstate
  CAMUNDA_HOST = orchestration-cluster.$(BENCHMARK_NAME)-oc.service.local
else
  PREFIX = load_test$(BENCHMARK_NUMBER)
  BACKEND_KEY = load_test$(BENCHMARK_NUMBER)/load_test$(BENCHMARK_NUMBER).tfstate
  CAMUNDA_HOST = orchestration-cluster.benchmark$(BENCHMARK_NUMBER)-oc.service.local
endif
TFVARS_FILE = prod/terraform.tfvars

include ../shared.mk
