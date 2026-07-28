#!/usr/bin/env bash
#
# region-disconnect-run.sh
#
# Runs a region disconnect FIS experiment with pre- and post-experiment
# cluster health verification.
#
# Flow:
#   1. Pre-check: verify the cluster is healthy before the experiment
#   2. Start the FIS experiment (isolates the whole target region)
#   3. Wait for the experiment to complete (connectivity restored at the end)
#   4. Post-check: verify the cluster recovers within a timeout after the
#      region rejoins
#   5. Print a summary report
#
# NOTE: during the disruption, cross-region Raft partitions will lose quorum
# and the topology will report region_1 brokers as unreachable. That is the
# expected in-experiment behavior — the pass criterion is whether the cluster
# returns to full health AFTER connectivity is restored.
#
# Prerequisites:
#   - FIS-Admin role assumed (source ./experiments/assume-fis-role.sh)
#   - Template created (./experiments/region-disconnect/region-disconnect-create.sh)
#   - region_0 primary ALB endpoint reachable for health checks (over VPN)
#
# Usage:
#   ./experiments/region-disconnect/region-disconnect-run.sh --name 6-region-disconnect-dev --endpoint <REGION_0_ALB_DNS>
#   ./experiments/region-disconnect/region-disconnect-run.sh --id EXT123 --endpoint <REGION_0_ALB_DNS> --recovery-wait 600
#
# Options:
#   --name           Template name (or use --id)
#   --id             Template ID (or use --name)
#   --endpoint       region_0 primary ALB DNS for Camunda topology API (required)
#   --region         Region where the FIS template lives (default: us-east-1)
#   --recovery-wait  Seconds to wait for post-experiment recovery (default: 300)
#   --skip-pre-check Skip the pre-experiment health check
#   --yes            Skip confirmation prompt
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${EXPERIMENTS_DIR}/lib/common.sh"

# FIS template lives in the target region (us-east-1). Health checks hit the
# region_0 primary ALB, which is a separate --endpoint argument.
AWS_REGION="${AWS_REGION:-us-east-1}"
TEMPLATE_ID=""
TEMPLATE_NAME=""
ENDPOINT=""
# PREFIX/ECS_CLUSTER left empty: the health check only queries the topology
# API via --endpoint; no cross-region ECS service lookup is attempted.
PREFIX=""
ECS_CLUSTER=""
RECOVERY_WAIT=300
SKIP_PRE_CHECK=false
AUTO_YES=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --id)             TEMPLATE_ID="$2";    shift 2 ;;
    --name)           TEMPLATE_NAME="$2";  shift 2 ;;
    --endpoint)       ENDPOINT="$2";       shift 2 ;;
    --region)         AWS_REGION="$2";     shift 2 ;;
    --recovery-wait)  RECOVERY_WAIT="$2";  shift 2 ;;
    --skip-pre-check) SKIP_PRE_CHECK=true; shift ;;
    --yes)            AUTO_YES=true;       shift ;;
    -h|--help)
      echo "Usage: $0 --name <NAME> --endpoint <REGION_0_ALB_DNS> [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --name           Template name (or use --id)"
      echo "  --id             Template ID (or use --name)"
      echo "  --endpoint       region_0 primary ALB DNS for health checks (required)"
      echo "  --region         Region where the FIS template lives (default: us-east-1)"
      echo "  --recovery-wait  Seconds to wait for recovery (default: 300)"
      echo "  --skip-pre-check Skip pre-experiment health check"
      echo "  --yes            Skip confirmation prompt"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${ENDPOINT}" ]]; then
  echo "ERROR: --endpoint is required for health verification."
  echo "Use the region_0 (primary, eu-west-1) ALB DNS — reachable over VPN."
  echo "Usage: $0 --name <NAME> --endpoint <REGION_0_ALB_DNS>"
  exit 1
fi

# --- Resolve template ---
resolve_template

# --- Get template details ---
get_template_info

DESCRIPTION=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.description')
TARGET_REGION=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.target_region // "unknown"')
DURATION=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.actions[].parameters.duration // "unknown"')

echo "============================================="
echo "  Region Disconnect Experiment"
echo "============================================="
echo ""
echo "Template ID:       ${TEMPLATE_ID}"
echo "Description:       ${DESCRIPTION}"
echo "Target region:     ${TARGET_REGION}"
echo "Duration:          ${DURATION}"
echo "Recovery wait:     ${RECOVERY_WAIT}s"
echo "Health endpoint:   ${ENDPOINT} (region_0 primary)"
echo ""

# ========================================
# PHASE 1: Pre-experiment health check
# ========================================
run_pre_check

# ========================================
# Confirmation
# ========================================
confirm_experiment \
  "This experiment will isolate ALL private subnets in region '${TARGET_REGION}' for ${DURATION}." \
  "Cross-region partitions will lose quorum for the duration."

# ========================================
# PHASE 2: Run experiment
# ========================================
start_experiment
wait_for_experiment

# ========================================
# PHASE 3: Post-experiment health check
# ========================================
run_post_check

# ========================================
# PHASE 4: Summary Report
# ========================================
print_summary_header

REPORT=$(jq -n \
  --arg experiment_id "${EXPERIMENT_ID}" \
  --arg template_id "${TEMPLATE_ID}" \
  --arg template_name "${TEMPLATE_NAME}" \
  --arg target_region "${TARGET_REGION}" \
  --arg duration "${DURATION}" \
  --arg experiment_state "${CURRENT_STATE}" \
  --arg experiment_reason "${EXPERIMENT_STATE_REASON}" \
  --arg experiment_start "${EXPERIMENT_START}" \
  --arg experiment_end "${EXPERIMENT_END}" \
  --argjson pre_check "${PRE_CHECK_RESULT}" \
  --argjson post_check "${POST_CHECK_RESULT}" \
  --arg recovery_status "${RECOVERY_STATUS}" \
  --argjson recovery_duration_seconds "${RECOVERY_DURATION}" \
  '{
    experiment_id: $experiment_id,
    template_id: $template_id,
    template_name: $template_name,
    target_region: $target_region,
    duration: $duration,
    experiment: {
      state: $experiment_state,
      reason: $experiment_reason,
      start: $experiment_start,
      end: $experiment_end
    },
    pre_check: $pre_check,
    post_check: $post_check,
    recovery: {
      status: $recovery_status,
      duration_seconds: $recovery_duration_seconds
    }
  }')

echo "${REPORT}" | jq '.'

exit_with_result
