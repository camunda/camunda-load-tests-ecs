# Shared Makefile for benchmark infrastructure
# Included by per-environment Makefiles (dev/Makefile, prod/Makefile)
# Run from the environment subdirectory: cd dev && make plan

# These must be set by the including Makefile
BENCHMARK_NUMBER ?= $(error BENCHMARK_NUMBER not set)
PREFIX ?= $(error PREFIX not set)
BACKEND_KEY ?= $(error BACKEND_KEY not set)
TFVARS_FILE ?= $(error TFVARS_FILE not set)
ECS_CLUSTER ?= $(error ECS_CLUSTER not set)
TERRAFORM_DIR ?= ..

CAMUNDA_IMAGE ?= camunda/camunda:SNAPSHOT
S3_BUCKET_NAME = $(PREFIX)-oc-bucket

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

.PHONY: help init plan apply deploy force-cleanup destroy-services empty-s3 destroy destroy-with-bucket clean show-vars validate-prefix

help: ## Show this help message
	@echo "Benchmark Terraform Management — $(ENV)"
	@echo ""
	@echo "Usage: make <target> [VARIABLES...]"
	@echo ""
	@echo "Targets:"
	@echo "  help              Show this help message"
	@echo "  init              Initialize Terraform with backend configuration"
	@echo "  plan              Plan the infrastructure changes"
	@echo "  apply             Apply the infrastructure changes"
	@echo "  deploy            Alias for apply"
	@echo "  destroy-services  Destroy only ECS services via Terraform (step 1 of safe destroy)"
	@echo "  force-cleanup     AWS CLI cleanup: stop ECS service, remove Service Discovery orphans, empty S3"
	@echo "  empty-s3          Empty S3 buckets after application shutdown"
	@echo "  destroy           Destroy all infrastructure"
	@echo "  destroy-with-bucket  Safely destroy infrastructure with S3 bucket cleanup"
	@echo "  clean             Clean terraform files"
	@echo "  show-vars         Show current variable values"
	@echo ""
	@echo "Variables:"
	@echo "  BENCHMARK_NUMBER  Benchmark instance number (default: 1)"
	@echo "  CAMUNDA_IMAGE     Docker image for Camunda (default: camunda/camunda:SNAPSHOT)"
	@echo "  TERRAFORM         Binary to use: terraform or tofu (auto-detected)"

# AWS target group names are limited to 32 characters.
# The orchestration-cluster module creates "<PREFIX>-oc-tg-26500" (12-char suffix).
# PREFIX must be at most 20 characters.
MAX_PREFIX_LEN = 20
validate-prefix:
	@if [ $$(printf '%s' '$(PREFIX)' | wc -c) -gt $(MAX_PREFIX_LEN) ]; then \
		echo "ERROR: PREFIX '$(PREFIX)' is $$(printf '%s' '$(PREFIX)' | wc -c) chars, exceeds $(MAX_PREFIX_LEN) char limit."; \
		echo "AWS target group names are limited to 32 chars; longest derived name: $(PREFIX)-oc-tg-26500"; \
		exit 1; \
	fi

init: ## Initialize Terraform with backend configuration
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) init -backend-config="key=$(BACKEND_KEY)" -reconfigure

plan: validate-prefix init ## Plan the infrastructure changes
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) plan \
		-var-file=$(TFVARS_FILE) \
		-var='camunda_image=$(CAMUNDA_IMAGE)' \
		-var="prefix=$(PREFIX)"

apply: validate-prefix init ## Apply the infrastructure changes
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) apply $(AUTO_APPROVE) \
		-var-file=$(TFVARS_FILE) \
		-var='camunda_image=$(CAMUNDA_IMAGE)' \
		-var="prefix=$(PREFIX)"

deploy: apply ## Alias for apply

force-cleanup: ## AWS CLI cleanup: stop ECS, delete service, clean Service Discovery, empty S3
	@echo "=== Force cleanup for $(PREFIX) in cluster $(ECS_CLUSTER) ==="
	@# 1. Delete the ECS service (--force stops running tasks)
	@echo "[1/3] Deleting ECS service $(PREFIX)-oc-orchestration-cluster..."
	@aws ecs delete-service \
		--cluster $(ECS_CLUSTER) \
		--service $(PREFIX)-oc-orchestration-cluster \
		--force --output text --query 'service.status' 2>/dev/null \
		&& echo "Service deleted, waiting 15s for drain..." && sleep 15 \
		|| echo "Service not found or already deleted"
	@# 2. Clean up Service Discovery services from the namespace
	@echo "[2/3] Cleaning up Service Discovery namespace $(PREFIX)-oc-sc..."
	@NAMESPACE_ID=$$(aws servicediscovery list-namespaces \
		--query "Namespaces[?Name=='$(PREFIX)-oc-sc'].Id" --output text 2>/dev/null); \
	if [ -n "$$NAMESPACE_ID" ] && [ "$$NAMESPACE_ID" != "None" ]; then \
		SERVICE_IDS=$$(aws servicediscovery list-services \
			--filters Name=NAMESPACE_ID,Values=$$NAMESPACE_ID \
			--query 'Services[].Id' --output text 2>/dev/null); \
		for SVC_ID in $$SERVICE_IDS; do \
			INSTANCE_IDS=$$(aws servicediscovery list-instances \
				--service-id $$SVC_ID --query 'Instances[].Id' --output text 2>/dev/null); \
			for INST_ID in $$INSTANCE_IDS; do \
				aws servicediscovery deregister-instance \
					--service-id $$SVC_ID --instance-id $$INST_ID 2>/dev/null || true; \
			done; \
			aws servicediscovery delete-service --id $$SVC_ID 2>/dev/null || true; \
		done; \
		echo "Service Discovery cleaned up"; \
	else \
		echo "Namespace not found, skipping"; \
	fi
	@# 3. Empty S3 bucket
	@echo "[3/3] Emptying S3 bucket $(S3_BUCKET_NAME)..."
	@aws s3 rm "s3://$(S3_BUCKET_NAME)" --recursive --quiet 2>/dev/null || echo "Bucket empty or doesn't exist"
	@echo "=== Force cleanup complete ==="

destroy-services: init ## Destroy only ECS services (step 1 of safe destroy)
	@echo "Stopping ECS services..."
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) destroy $(AUTO_APPROVE) \
		-var-file=$(TFVARS_FILE) \
		-var="prefix=$(PREFIX)" \
		-target="module.orchestration_cluster.aws_ecs_service.orchestration_cluster" || true

empty-s3: ## Empty S3 buckets after application shutdown (step 2 of safe destroy)
	@echo "Emptying S3 buckets after shutdown..."
	@echo "Bucket name: $(S3_BUCKET_NAME)"
	aws s3 rm "s3://$(S3_BUCKET_NAME)" --recursive --quiet || echo "Bucket $(S3_BUCKET_NAME) already empty or doesn't exist"

destroy: init ## Destroy all infrastructure
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) destroy $(AUTO_APPROVE) \
		-var-file=$(TFVARS_FILE) \
		-var="prefix=$(PREFIX)"

destroy-with-bucket: init ## Safely destroy: force-cleanup AWS resources, then terraform destroy
	$(MAKE) force-cleanup
	@echo "Running terraform destroy..."
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) destroy $(AUTO_APPROVE) \
		-var-file=$(TFVARS_FILE) \
		-var="prefix=$(PREFIX)"

clean: ## Clean terraform files
	rm -rf $(TERRAFORM_DIR)/.terraform $(TERRAFORM_DIR)/.terraform.lock.hcl

show-vars: ## Show current variable values
	@echo "ENV:            $(ENV)"
	@echo "TERRAFORM:      $(TERRAFORM)"
	@echo "TERRAFORM_DIR:  $(TERRAFORM_DIR)"
	@echo "BENCHMARK_NUMBER: $(BENCHMARK_NUMBER)"
	@echo "CAMUNDA_IMAGE:  $(CAMUNDA_IMAGE)"
	@echo "PREFIX:         $(PREFIX)"
	@echo "BACKEND_KEY:    $(BACKEND_KEY)"
	@echo "TFVARS_FILE:    $(TFVARS_FILE)"
	@echo "S3_BUCKET_NAME: $(S3_BUCKET_NAME)"