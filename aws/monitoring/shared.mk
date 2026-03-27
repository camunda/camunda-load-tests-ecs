# Shared Makefile for monitoring infrastructure
# Included by per-environment Makefiles (dev/Makefile, prod/Makefile)
# Run from the environment subdirectory: cd dev && make plan

# These must be set by the including Makefile
BACKEND_KEY ?= $(error BACKEND_KEY not set)
TFVARS_FILE ?= $(error TFVARS_FILE not set)
TERRAFORM_DIR ?= ..

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

.PHONY: help init plan apply deploy destroy clean show-vars

help: ## Show this help message
	@echo "Monitoring Terraform Management — $(ENV)"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  help       Show this help message"
	@echo "  init       Initialize Terraform with backend configuration"
	@echo "  plan       Plan the infrastructure changes"
	@echo "  apply      Apply the infrastructure changes"
	@echo "  deploy     Alias for apply"
	@echo "  destroy    Destroy all monitoring infrastructure"
	@echo "  clean      Clean terraform files"
	@echo "  show-vars  Show current variable values"

init: ## Initialize Terraform with backend configuration
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) init -backend-config="key=$(BACKEND_KEY)" -reconfigure

plan: init ## Plan the infrastructure changes
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) plan -var-file=$(TFVARS_FILE)

apply: init ## Apply the infrastructure changes
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) apply $(AUTO_APPROVE) -var-file=$(TFVARS_FILE)

deploy: apply ## Alias for apply

destroy: init ## Destroy all monitoring infrastructure
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) destroy $(AUTO_APPROVE) -var-file=$(TFVARS_FILE)

clean: ## Clean terraform files
	rm -rf $(TERRAFORM_DIR)/.terraform $(TERRAFORM_DIR)/.terraform.lock.hcl

show-vars: ## Show current variable values
	@echo "ENV:            $(ENV)"
	@echo "TERRAFORM:      $(TERRAFORM)"
	@echo "TERRAFORM_DIR:  $(TERRAFORM_DIR)"
	@echo "BACKEND_KEY:    $(BACKEND_KEY)"
	@echo "TFVARS_FILE:    $(TFVARS_FILE)"
