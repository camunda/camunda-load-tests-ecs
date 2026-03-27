ENV = dev
BENCHMARK_NUMBER ?= 1
# Allow overriding PREFIX directly via BENCHMARK_NAME (e.g., weekly-2026-03-17)
# Falls back to the numeric convention (dev-load_test1) when BENCHMARK_NAME is not set
ifdef BENCHMARK_NAME
  PREFIX = dev-$(BENCHMARK_NAME)-lt
  BACKEND_KEY = dev/load_tests/$(BENCHMARK_NAME)-lt.tfstate
  CAMUNDA_HOST = orchestration-cluster.dev-$(BENCHMARK_NAME)-oc.service.local
else
  PREFIX = dev-load_test$(BENCHMARK_NUMBER)
  BACKEND_KEY = dev/load_test$(BENCHMARK_NUMBER)/load_test$(BENCHMARK_NUMBER).tfstate
  CAMUNDA_HOST = orchestration-cluster.dev-benchmark$(BENCHMARK_NUMBER)-oc.service.local
endif
TFVARS_FILE = dev/terraform.tfvars

include ../shared.mk
