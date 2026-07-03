# Shared Makefile for dual-region vpc/ state
# Included by per-environment Makefiles (prod/Makefile)
# Run from the environment subdirectory: cd prod && make plan

BACKEND_KEY ?= $(error BACKEND_KEY not set)
TFVARS_FILE ?= $(error TFVARS_FILE not set)
TERRAFORM_DIR ?= ..

ifdef CI
  AUTO_APPROVE = -auto-approve
else ifdef GITHUB_ACTIONS
  AUTO_APPROVE = -auto-approve
else
  AUTO_APPROVE =
endif

TERRAFORM ?= terraform
ifeq ($(shell which tofu 2>/dev/null),)
else ifeq ($(shell which terraform 2>/dev/null),)
  TERRAFORM = tofu
endif

.PHONY: help init plan apply deploy destroy clean show-vars

help: ## Show this help message
	@echo "Dual-Region VPC — $(ENV)"
	@echo "Usage: make <target>"
	@echo "  init | plan | apply | deploy | destroy | clean | show-vars"

init: ## Initialize Terraform with backend configuration
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) init -backend-config="key=$(BACKEND_KEY)" -reconfigure

plan: init ## Plan the infrastructure changes
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) plan -var-file=$(TFVARS_FILE)

apply: init ## Apply the infrastructure changes
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) apply $(AUTO_APPROVE) -var-file=$(TFVARS_FILE)

deploy: apply ## Alias for apply

destroy: init ## Destroy the cross-region networking (peering/TGW). Must run AFTER infra/app are destroyed.
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) destroy $(AUTO_APPROVE) -var-file=$(TFVARS_FILE)

clean: ## Clean terraform files
	rm -rf $(TERRAFORM_DIR)/.terraform $(TERRAFORM_DIR)/.terraform.lock.hcl

show-vars: ## Show current variable values
	@echo "TERRAFORM:      $(TERRAFORM)"
	@echo "TERRAFORM_DIR:  $(TERRAFORM_DIR)"
	@echo "BACKEND_KEY:    $(BACKEND_KEY)"
	@echo "TFVARS_FILE:    $(TFVARS_FILE)"
