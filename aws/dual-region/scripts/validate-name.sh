#!/usr/bin/env bash
# Validates a dual-region cluster_name against the AWS 32-char resource-name
# limit. The known-good name "dev-camunda-dr" (14 chars) deploys cleanly, so
# any name of length <= 14 is guaranteed safe for the derived resource names
# (e.g. <name>-r0-oc-tg-26500).
set -euo pipefail

NAME="${1:?usage: validate-name.sh <cluster_name>}"
MAX=14

if [[ "$NAME" != dev-* ]]; then
  echo "::error::cluster_name '$NAME' must start with 'dev-' (monitoring sidecar filters dev-* namespaces)" >&2
  exit 1
fi

if (( ${#NAME} > MAX )); then
  echo "::error::cluster_name '$NAME' is ${#NAME} chars, exceeds the ${MAX}-char safe limit (derived names would risk the AWS 32-char cap)" >&2
  exit 1
fi

echo "✅ cluster_name '$NAME' (${#NAME} chars) is within the ${MAX}-char safe limit"
