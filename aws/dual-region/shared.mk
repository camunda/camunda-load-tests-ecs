# Shared Makefile for the dual-region states (vpc/, infra/, app/)
# Included by per-environment Makefiles (dev/Makefile, prod/Makefile)
# Run from the environment subdirectory: cd dev && make plan

BACKEND_KEY ?= $(error BACKEND_KEY not set)
TFVARS_FILE ?= $(error TFVARS_FILE not set)
# Human-readable name of the including state, shown by `make help`.
STATE_DESC ?= $(error STATE_DESC not set)
TERRAFORM_DIR ?= ..

# Extra -var flags injected by the per-environment Makefile (e.g. rotating
# cluster_name and remote-state keys). Empty for a plain single-name deploy.
EXTRA_TF_VARS ?=

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
	@echo "$(STATE_DESC) — $(ENV)"
	@echo "Usage: make <target>"
	@echo "  init | plan | apply | deploy | destroy | clean | show-vars"
	@echo "  FORCE_DEPLOYMENT=1 make apply  -- force a new ECS deployment (app state only)"

init: ## Initialize Terraform with backend configuration
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) init -backend-config="key=$(BACKEND_KEY)" -reconfigure

plan: init ## Plan the infrastructure changes
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) plan -var-file=$(TFVARS_FILE) $(EXTRA_TF_VARS) $(if $(FORCE_DEPLOYMENT),-var="force_deployment=true")

apply: init ## Apply the infrastructure changes
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) apply $(AUTO_APPROVE) -var-file=$(TFVARS_FILE) $(EXTRA_TF_VARS) $(if $(FORCE_DEPLOYMENT),-var="force_deployment=true")
ifdef FORCE_DEPLOYMENT
	# force_new_deployment is a sticky boolean in state: it only triggers an ECS
	# deployment on a false->true diff, so flip it back to false immediately or
	# the next FORCE_DEPLOYMENT=1 apply would see true->true (no diff, no-op).
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) apply $(AUTO_APPROVE) -var-file=$(TFVARS_FILE) $(EXTRA_TF_VARS)
endif

deploy: apply ## Alias for apply

destroy: init ## Destroy this state. States must be destroyed in order: app → infra → vpc.
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) destroy $(AUTO_APPROVE) -var-file=$(TFVARS_FILE) $(EXTRA_TF_VARS)

clean: ## Clean terraform files
	rm -rf $(TERRAFORM_DIR)/.terraform $(TERRAFORM_DIR)/.terraform.lock.hcl

show-vars: ## Show current variable values
	@echo "TERRAFORM:      $(TERRAFORM)"
	@echo "TERRAFORM_DIR:  $(TERRAFORM_DIR)"
	@echo "BACKEND_KEY:    $(BACKEND_KEY)"
	@echo "TFVARS_FILE:    $(TFVARS_FILE)"
