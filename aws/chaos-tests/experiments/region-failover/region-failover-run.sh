#!/usr/bin/env bash
#
# region-failover-run.sh
#
# Compound DR drill: primary region (region_0, eu-west-1) failure + Aurora
# Global cross-region failover.
#
# Steps:
#   1. Baseline health snapshot (region_1 survivor endpoint)
#   2. Start FIS network isolation of ALL region_0 private subnets
#      (uses a template created by region-disconnect-create.sh --region eu-west-1)
#   3. Promote the Aurora secondary (us-east-1) to writer
#      (aurora-global-failover.sh)
#   4. Post-failover snapshot against the survivor region
#   5. Wait for FIS to restore region_0 connectivity, final snapshot, report
#
# IMPORTANT — what this does and does NOT verify:
#   - It verifies the DATABASE failover: the Aurora global writer moves to
#     us-east-1 and the global writer endpoint repoints. Applications using
#     aurora_jdbc_url reconnect without config changes.
#   - It does NOT auto-heal the Zeebe cluster. Isolating region_0's 2 brokers
#     (RF2, 4 partitions) loses quorum on cross-region partitions. Full Zeebe
#     recovery requires the documented Camunda dual-region region-recovery
#     runbook (redeploy/scale in the survivor) — out of scope here. Cluster
#     health snapshots are therefore INFORMATIONAL, not pass/fail gates.
#
# Prerequisites:
#   - FIS-Admin role assumed (source ./experiments/assume-fis-role.sh)
#   - FIS template for region_0 created, e.g.:
#       ./experiments/region-disconnect/region-disconnect-create.sh \
#           --region eu-west-1 --vpc camunda-dev-vpc --name 7-region-failover-primary-dev
#   - region_1 (us-east-1) ALB endpoint reachable over VPN
#
# Usage:
#   ./experiments/region-failover/region-failover-run.sh \
#       --name 7-region-failover-primary-dev \
#       --endpoint <REGION_1_ALB_DNS> \
#       --db-mode switchover
#
# Options:
#   --name        FIS template name for region_0 isolation (or --id)
#   --id          FIS template ID
#   --endpoint    region_1 survivor ALB DNS for health snapshots (required)
#   --fis-region  Region where the FIS template lives (default: eu-west-1)
#   --db-mode     Aurora failover mode: switchover | failover (default: switchover)
#   --db-region   Region to issue the Aurora API call from (default: us-east-1)
#   --yes         Skip confirmation prompts
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${EXPERIMENTS_DIR}/lib/common.sh"

AWS_REGION="eu-west-1"   # FIS template region (region_0)
TEMPLATE_ID=""
TEMPLATE_NAME=""
ENDPOINT=""
DB_MODE="switchover"
DB_REGION="us-east-1"
AUTO_YES=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --id)         TEMPLATE_ID="$2";   shift 2 ;;
    --name)       TEMPLATE_NAME="$2"; shift 2 ;;
    --endpoint)   ENDPOINT="$2";      shift 2 ;;
    --fis-region) AWS_REGION="$2";    shift 2 ;;
    --db-mode)    DB_MODE="$2";       shift 2 ;;
    --db-region)  DB_REGION="$2";     shift 2 ;;
    --yes)        AUTO_YES=true;      shift ;;
    -h|--help)
      echo "Usage: $0 --name <FIS_TEMPLATE> --endpoint <REGION_1_ALB_DNS> [--db-mode switchover|failover] [--yes]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "${ENDPOINT}" ]]; then
  echo "ERROR: --endpoint (region_1 survivor ALB DNS) is required."
  exit 1
fi

# Informational cluster-health snapshot — never gates the run.
snapshot() {
  local label="$1"
  echo "--- Snapshot: ${label} ---"
  "${EXPERIMENTS_DIR}/verify-cluster-health.sh" --endpoint "${ENDPOINT}" --quiet 2>/dev/null \
    | jq '.' || echo "(cluster health unreachable — expected while a region is isolated)"
  echo ""
}

resolve_template
get_template_info
DESCRIPTION=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.description')
TARGET_REGION=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.tags.target_region // "unknown"')
DURATION=$(echo "${TEMPLATE_INFO}" | jq -r '.experimentTemplate.actions[].parameters.duration // "unknown"')

echo "============================================="
echo "  Region Failover DR Drill"
echo "============================================="
echo "FIS template:      ${TEMPLATE_ID} (${DESCRIPTION})"
echo "Isolated region:   ${TARGET_REGION}  for ${DURATION}"
echo "Aurora DB mode:    ${DB_MODE}  (issued from ${DB_REGION})"
echo "Survivor endpoint: ${ENDPOINT} (region_1)"
echo ""

confirm_experiment \
  "This will isolate region '${TARGET_REGION}' AND ${DB_MODE} the Aurora writer to the survivor." \
  "Zeebe quorum will be lost on cross-region partitions for the duration."

# Step 1 — baseline
echo "=== Step 1: baseline health ==="
snapshot "before"

# Step 2 — isolate region_0
echo "=== Step 2: isolate ${TARGET_REGION} (FIS) ==="
start_experiment      # uses TEMPLATE_ID + AWS_REGION (FIS region)

# Step 3 — Aurora failover
echo "=== Step 3: Aurora global ${DB_MODE} ==="
DB_RESULT=0
"${EXPERIMENTS_DIR}/aurora/aurora-global-failover.sh" \
  --mode "${DB_MODE}" --region "${DB_REGION}" --yes || DB_RESULT=$?

# Step 4 — post-failover snapshot (survivor)
echo "=== Step 4: post-failover snapshot (survivor) ==="
snapshot "after DB failover (Zeebe quorum expected degraded)"

# Step 5 — wait for FIS to restore region_0, final snapshot
echo "=== Step 5: wait for region reconnect ==="
wait_for_experiment
snapshot "after region reconnect"

echo "============================================="
echo "  DR Drill Summary"
echo "============================================="
echo "Isolated region:      ${TARGET_REGION}"
echo "FIS experiment state: ${CURRENT_STATE}"
echo "Aurora ${DB_MODE}:     $([[ ${DB_RESULT} -eq 0 ]] && echo PASS || echo FAIL)"
echo ""
echo "NOTE: Zeebe cluster recovery is NOT automated — run the Camunda"
echo "dual-region region-recovery runbook in the survivor if needed."
if [[ "${DB_MODE}" == "failover" ]]; then
  echo "NOTE: 'failover' detached the old primary — rebuild/re-add it to the"
  echo "global cluster to restore dual-region redundancy."
fi
