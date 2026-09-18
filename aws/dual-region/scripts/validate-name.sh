#!/usr/bin/env bash
# Validates a dual-region cluster_name against the tightest AWS name limit
# among the resources it feeds: the OpenSearch domain name, which AWS caps at
# 28 chars. infra/opensearch.tf builds it as "<cluster_name>-r0-opensearch" /
# "-r1-opensearch" (14 chars of suffix), so 28 - 14 = 14 chars of budget.
#
# The ALB/NLB and target-group names are NOT the binding limit even though
# their AWS cap is 32: infra/lb.tf already truncates via
# substr(cluster_name, 0, 14) and the orchestration-cluster/connectors modules
# use substr(prefix, 0, 17) (e.g. <17>-orc-tg-26500 = 30 chars), so they can
# never overflow. Other derived names are far looser (IAM role 64, Aurora
# cluster identifier 63, ECS cluster / security group 255).
#
# The required "dev-" prefix consumes 4 of the 14, leaving 10 chars for
# BENCHMARK_NAME (the known-good "dev-camunda-dr" uses all 14).
set -euo pipefail

NAME="${1:?usage: validate-name.sh <cluster_name>}"
MAX=14

if [[ "$NAME" != dev-* ]]; then
  echo "::error::cluster_name '$NAME' must start with 'dev-' (monitoring sidecar filters dev-* namespaces)" >&2
  exit 1
fi

if (( ${#NAME} > MAX )); then
  echo "::error::cluster_name '$NAME' is ${#NAME} chars, exceeds the ${MAX}-char safe limit (<name>-r0-opensearch would exceed the AWS 28-char OpenSearch domain-name cap)" >&2
  exit 1
fi

echo "✅ cluster_name '$NAME' (${#NAME} chars) is within the ${MAX}-char safe limit"
