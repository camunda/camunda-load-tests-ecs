# Shared Makefile for the C7 benchmark on ECS. Same conventions as aws/benchmark and
# aws/load_test in camunda/camunda-load-tests-ecs. Run from dev/: cd dev && make plan

ENV ?= $(error ENV not set)
PREFIX ?= $(error PREFIX not set)
BACKEND_KEY ?= $(error BACKEND_KEY not set)
TFVARS_FILE ?= $(error TFVARS_FILE not set)
ECS_CLUSTER ?= $(error ECS_CLUSTER not set)
TERRAFORM_DIR ?= ..

ENGINE_IMAGE ?= registry.camunda.cloud/team-zeebe/c7-benchmark-engine:7.24.0-SNAPSHOT
LOAD_TESTER_IMAGE ?= registry.camunda.cloud/team-zeebe/c7-benchmark-load-tester:7.24.0-SNAPSHOT
RESULTS_IMAGE ?= registry.camunda.cloud/team-zeebe/c7-benchmark-results:latest
ENGINE_COUNT ?= 1
STARTER_RATE ?= 150
WORKER_COUNT ?= 3
HISTORY_LEVEL ?= full
AURORA_INSTANCE_CLASS ?= db.r7g.large
RESULTS_BUCKET ?=
PROMETHEUS_URL ?= http://prometheus.$(ENV)-monitoring.service.local:9090
FORCE_NEW_DEPLOYMENT ?= false

# Report window for `make results`: RFC3339 or Unix seconds. Default: the last 30 minutes.
END ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
DURATION ?= 1800
START ?=
RUN_ID ?= $(PREFIX)-$(shell date -u +%Y%m%d-%H%M)

ifdef CI
  AUTO_APPROVE = -auto-approve
else ifdef GITHUB_ACTIONS
  AUTO_APPROVE = -auto-approve
else
  AUTO_APPROVE =
endif

TERRAFORM ?= terraform
ifeq ($(shell which terraform 2>/dev/null),)
  ifneq ($(shell which tofu 2>/dev/null),)
    TERRAFORM = tofu
  endif
endif

TF_VARS = \
	-var-file=$(TFVARS_FILE) \
	-var="prefix=$(PREFIX)" \
	-var="force_new_deployment=$(FORCE_NEW_DEPLOYMENT)" \
	-var="engine_image=$(ENGINE_IMAGE)" \
	-var="load_tester_image=$(LOAD_TESTER_IMAGE)" \
	-var="results_image=$(RESULTS_IMAGE)" \
	-var="engine_count=$(ENGINE_COUNT)" \
	-var="starter_rate=$(STARTER_RATE)" \
	-var="worker_count=$(WORKER_COUNT)" \
	-var="history_level=$(HISTORY_LEVEL)" \
	-var="aurora_instance_class=$(AURORA_INSTANCE_CLASS)" \
	-var="results_bucket=$(RESULTS_BUCKET)" \
	-var="prometheus_url=$(PROMETHEUS_URL)"

.PHONY: help init plan apply deploy destroy restart results show-vars clean

help:
	@echo "C7 benchmark on ECS ($(ENV)), prefix $(PREFIX)"
	@echo ""
	@echo "  make deploy      Create Aurora + engine + starter + workers + postgres-exporter"
	@echo "  make apply STARTER_RATE=300   Change parameters of a running benchmark"
	@echo "  make results     Write a results folder for the last DURATION seconds (or START/END) to S3"
	@echo "  make destroy     Delete everything (Aurora included)"
	@echo ""
	@echo "Variables: BENCHMARK_NAME BENCHMARK_NUMBER ENGINE_IMAGE LOAD_TESTER_IMAGE ENGINE_COUNT"
	@echo "           STARTER_RATE WORKER_COUNT HISTORY_LEVEL AURORA_INSTANCE_CLASS RESULTS_BUCKET"
	@echo "           START END DURATION RUN_ID"

init:
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) init -backend-config="key=$(BACKEND_KEY)" -reconfigure

plan: init
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) plan $(TF_VARS)

apply: init
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) apply $(AUTO_APPROVE) $(TF_VARS)

deploy: apply

restart:
	$(MAKE) apply FORCE_NEW_DEPLOYMENT=true

destroy: init
	$(TERRAFORM) -chdir=$(TERRAFORM_DIR) destroy $(AUTO_APPROVE) $(TF_VARS)

# Runs the results task inside the VPC and waits for it. Output: s3://$(RESULTS_BUCKET)/c7/$(RUN_ID)/
results: init
	@test -n "$(RESULTS_BUCKET)" || (echo "ERROR: set RESULTS_BUCKET (see aws/c7_results)"; exit 1)
	@td=$$($(TERRAFORM) -chdir=$(TERRAFORM_DIR) output -raw results_task_definition); \
	net=$$($(TERRAFORM) -chdir=$(TERRAFORM_DIR) output -json results_network); \
	subnets=$$(echo "$$net" | python3 -c 'import json,sys;print(",".join(json.load(sys.stdin)["subnets"]))'); \
	sgs=$$(echo "$$net" | python3 -c 'import json,sys;print(",".join(json.load(sys.stdin)["security_groups"]))'); \
	overrides=$$(python3 -c 'import json,sys;print(json.dumps({"containerOverrides":[{"name":"results","environment":[{"name":k,"value":v} for k,v in zip(["RUN_ID","START","END","DURATION"],sys.argv[1:])]}]}))' "$(RUN_ID)" "$(START)" "$(END)" "$(DURATION)"); \
	arn=$$(aws ecs run-task --cluster $(ECS_CLUSTER) --launch-type FARGATE --task-definition "$$td" \
		--network-configuration "awsvpcConfiguration={subnets=[$$subnets],securityGroups=[$$sgs],assignPublicIp=DISABLED}" \
		--overrides "$$overrides" --query 'tasks[0].taskArn' --output text); \
	echo "Results task $$arn"; \
	aws ecs wait tasks-stopped --cluster $(ECS_CLUSTER) --tasks "$$arn"; \
	code=$$(aws ecs describe-tasks --cluster $(ECS_CLUSTER) --tasks "$$arn" --query 'tasks[0].containers[0].exitCode' --output text); \
	echo "Exit code $$code. Results: s3://$(RESULTS_BUCKET)/c7/$(RUN_ID)/"; \
	test "$$code" = "0"

show-vars:
	@echo "ENV=$(ENV) PREFIX=$(PREFIX) BACKEND_KEY=$(BACKEND_KEY) ECS_CLUSTER=$(ECS_CLUSTER)"
	@echo "ENGINE_IMAGE=$(ENGINE_IMAGE)"
	@echo "LOAD_TESTER_IMAGE=$(LOAD_TESTER_IMAGE)"
	@echo "ENGINE_COUNT=$(ENGINE_COUNT) STARTER_RATE=$(STARTER_RATE) WORKER_COUNT=$(WORKER_COUNT) HISTORY_LEVEL=$(HISTORY_LEVEL)"
	@echo "AURORA_INSTANCE_CLASS=$(AURORA_INSTANCE_CLASS) RESULTS_BUCKET=$(RESULTS_BUCKET) PROMETHEUS_URL=$(PROMETHEUS_URL)"

clean:
	rm -rf $(TERRAFORM_DIR)/.terraform $(TERRAFORM_DIR)/.terraform.lock.hcl
