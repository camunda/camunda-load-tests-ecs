# Shared Makefile for load test infrastructure
# Included by per-environment Makefiles (dev/Makefile, prod/Makefile)
# Run from the environment subdirectory: cd dev && make plan

# These must be set by the including Makefile
BENCHMARK_NUMBER ?= $(error BENCHMARK_NUMBER not set)
PREFIX ?= $(error PREFIX not set)
BACKEND_KEY ?= $(error BACKEND_KEY not set)
CAMUNDA_HOST ?= $(error CAMUNDA_HOST not set)
TFVARS_FILE ?= $(error TFVARS_FILE not set)
TERRAFORM_DIR ?= ..

FORCE_NEW_DEPLOYMENT ?= false
STARTER_IMAGE ?= registry.camunda.cloud/team-zeebe/starter:SNAPSHOT
WORKER_IMAGE ?= registry.camunda.cloud/team-zeebe/worker:SNAPSHOT
LOG_GROUP_NAME = /ecs/$(PREFIX)

# Auto-approve only in CI environments
ifdef CI
  AUTO_APPROVE = -auto-approve
else ifdef GITHUB_ACTIONS
  AUTO_APPROVE = -auto-approve
else
  AUTO_APPROVE =
endif

# Terraform binary selection (default: terraform, override with TERRAFORM=tofu)
TERRAFORM ?= terraform
ifeq ($(shell which tofu 2>/dev/null),)
  # tofu not found, use terraform
else ifeq ($(shell which terraform 2>/dev/null),)
  # terraform not found but tofu exists, use tofu
  TERRAFORM = tofu
endif

.PHONY: help init plan apply deploy destroy clean show-vars restart

help: ## Show this help message
	@echo "Load Test Terraform Management — $(ENV)"
	@echo ""
	@echo "Usage: make <target> [VARIABLES...]"
	@echo ""
	@echo "Targets:"
	@echo "  help              Show this help message"
	@echo "  init              Initialize Terraform with backend configuration"
	@echo "  plan              Plan the infrastructure changes"
	@echo "  apply             Apply the infrastructure changes"
	@echo "  deploy            Alias for apply"
	@echo "  destroy           Destroy all load test infrastructure"
	@echo "  clean             Clean terraform files"
	@echo "  show-vars         Show current variable values"
	@echo "  restart           Force restart of load test services"
	@echo ""
	@echo "Variables:"
	@echo "  BENCHMARK_NUMBER     Benchmark instance number (default: 1)"
	@echo "  FORCE_NEW_DEPLOYMENT Force service restart (default: false)"
	@echo "  STARTER_IMAGE        Starter image (default: registry.camunda.cloud/team-zeebe/starter:SNAPSHOT)"
	@echo "  WORKER_IMAGE         Worker image (default: registry.camunda.cloud/team-zeebe/worker:SNAPSHOT)"
	@echo "  TERRAFORM            Binary to use: terraform or tofu (auto-detected)"

init: ## Initialize Terraform with backend configuration
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) init -backend-config="key=$(BACKEND_KEY)" -reconfigure

plan: init ## Plan the infrastructure changes
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) plan \
		-var-file=$(TFVARS_FILE) \
		-var="force_new_deployment=$(FORCE_NEW_DEPLOYMENT)" \
		-var="prefix=$(PREFIX)" \
		-var="camunda_host=$(CAMUNDA_HOST)" \
		-var="starter_image=$(STARTER_IMAGE)" \
		-var="worker_image=$(WORKER_IMAGE)"

apply: init ## Apply the infrastructure changes
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) apply $(AUTO_APPROVE) \
		-var-file=$(TFVARS_FILE) \
		-var="force_new_deployment=$(FORCE_NEW_DEPLOYMENT)" \
		-var="prefix=$(PREFIX)" \
		-var="camunda_host=$(CAMUNDA_HOST)" \
		-var="starter_image=$(STARTER_IMAGE)" \
		-var="worker_image=$(WORKER_IMAGE)"

deploy: apply ## Alias for apply

destroy: init ## Destroy all load test infrastructure
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) destroy $(AUTO_APPROVE) \
		-var-file=$(TFVARS_FILE) \
		-var="prefix=$(PREFIX)" \
		-var="camunda_host=$(CAMUNDA_HOST)"

clean: ## Clean terraform files
	rm -rf $(TERRAFORM_DIR)/.terraform $(TERRAFORM_DIR)/.terraform.lock.hcl

show-vars: ## Show current variable values
	@echo "ENV:            $(ENV)"
	@echo "TERRAFORM:      $(TERRAFORM)"
	@echo "TERRAFORM_DIR:  $(TERRAFORM_DIR)"
	@echo "BENCHMARK_NUMBER: $(BENCHMARK_NUMBER)"
	@echo "FORCE_NEW_DEPLOYMENT: $(FORCE_NEW_DEPLOYMENT)"
	@echo "STARTER_IMAGE:  $(STARTER_IMAGE)"
	@echo "WORKER_IMAGE:   $(WORKER_IMAGE)"
	@echo "PREFIX:         $(PREFIX)"
	@echo "BACKEND_KEY:    $(BACKEND_KEY)"
	@echo "TFVARS_FILE:    $(TFVARS_FILE)"
	@echo "CAMUNDA_HOST:   $(CAMUNDA_HOST)"
	@echo "LOG_GROUP_NAME: $(LOG_GROUP_NAME)"

restart: ## Force restart of load test services
	$(MAKE) apply FORCE_NEW_DEPLOYMENT=true