#!/usr/bin/env bash
#
# aurora-global-failover.sh
#
# Promotes the secondary region of an Aurora Global Database to writer, to
# simulate / exercise a cross-region database failover. Two modes:
#
#   switchover (default) — planned, zero-data-loss role swap. Both clusters
#     stay in the global cluster; fully reversible by switching back. Use this
#     for repeatable DR drills.
#
#   failover — UNPLANNED failover with --allow-data-loss, for a true primary
#     region outage. This is DESTRUCTIVE: the old primary is detached from the
#     global cluster and must be rebuilt/re-added manually afterwards. Not
#     reversible with a single command.
#
# The Aurora Global "writer endpoint" auto-repoints to the new primary after
# either operation, so applications using it (see aurora_jdbc_url) reconnect
# without config changes.
#
# Prerequisites:
#   - AWS CLI v2, jq
#   - Logged in with rds:*GlobalCluster permissions
#
# Usage:
#   ./experiments/aurora/aurora-global-failover.sh                       # switchover, auto-discover
#   ./experiments/aurora/aurora-global-failover.sh --mode failover --yes
#   ./experiments/aurora/aurora-global-failover.sh --global-cluster dev-camunda-dr-global-db --region us-east-1
#
# Options:
#   --global-cluster  Global cluster identifier (default: auto-discover by 'camunda' match)
#   --mode            switchover | failover (default: switchover)
#   --region          Region to issue the API call from (default: us-east-1 = survivor)
#   --wait            Seconds to wait for the writer role to move (default: 300)
#   --yes             Skip confirmation prompt
#

set -euo pipefail

MODE="switchover"
GLOBAL_CLUSTER=""
AWS_REGION="us-east-1"
WAIT=300
AUTO_YES=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --global-cluster) GLOBAL_CLUSTER="$2"; shift 2 ;;
    --mode)           MODE="$2";           shift 2 ;;
    --region)         AWS_REGION="$2";     shift 2 ;;
    --wait)           WAIT="$2";           shift 2 ;;
    --yes)            AUTO_YES=true;       shift ;;
    -h|--help)
      echo "Usage: $0 [--mode switchover|failover] [--global-cluster ID] [--region REGION] [--wait SECS] [--yes]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ "${MODE}" != "switchover" && "${MODE}" != "failover" ]]; then
  echo "ERROR: --mode must be 'switchover' or 'failover'"
  exit 1
fi

# --- Discover the global cluster ---
if [[ -z "${GLOBAL_CLUSTER}" ]]; then
  GLOBAL_CLUSTER=$(aws rds describe-global-clusters \
    --region "${AWS_REGION}" \
    --query "GlobalClusters[?contains(GlobalClusterIdentifier,'camunda')].GlobalClusterIdentifier | [0]" \
    --output text)
  if [[ -z "${GLOBAL_CLUSTER}" || "${GLOBAL_CLUSTER}" == "None" ]]; then
    echo "ERROR: No global cluster matching 'camunda' found in ${AWS_REGION}."
    echo "Pass --global-cluster explicitly."
    exit 1
  fi
fi

# --- Inspect current members ---
MEMBERS=$(aws rds describe-global-clusters \
  --global-cluster-identifier "${GLOBAL_CLUSTER}" \
  --region "${AWS_REGION}" \
  --query "GlobalClusters[0].GlobalClusterMembers[].{arn:DBClusterArn,writer:IsWriter}" \
  --output json)

CURRENT_WRITER_ARN=$(echo "${MEMBERS}" | jq -r '.[] | select(.writer==true) | .arn')
TARGET_ARN=$(echo "${MEMBERS}" | jq -r '.[] | select(.writer==false) | .arn' | head -1)

if [[ -z "${TARGET_ARN}" || "${TARGET_ARN}" == "null" ]]; then
  echo "ERROR: No non-writer (secondary) member found to promote."
  echo "${MEMBERS}" | jq '.'
  exit 1
fi

writer_region() { echo "$1" | sed -E 's/^arn:aws:rds:([^:]+):.*/\1/'; }
CURRENT_WRITER_REGION=$(writer_region "${CURRENT_WRITER_ARN}")
TARGET_REGION=$(writer_region "${TARGET_ARN}")

echo "============================================="
echo "  Aurora Global Failover"
echo "============================================="
echo "Global cluster:  ${GLOBAL_CLUSTER}"
echo "Mode:            ${MODE}"
echo "Current writer:  ${CURRENT_WRITER_ARN}  (${CURRENT_WRITER_REGION})"
echo "Promote target:  ${TARGET_ARN}  (${TARGET_REGION})"
echo ""

if [[ "${AUTO_YES}" != "true" ]]; then
  if [[ "${MODE}" == "failover" ]]; then
    echo "WARNING: 'failover' with --allow-data-loss is DESTRUCTIVE."
    echo "The old primary (${CURRENT_WRITER_REGION}) will be detached from the"
    echo "global cluster and must be rebuilt/re-added manually afterwards."
  fi
  read -p "Promote ${TARGET_REGION} to writer via ${MODE}? (y/N) " -n 1 -r
  echo ""
  [[ $REPLY =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# --- Issue the operation ---
START=$(date +%s)
if [[ "${MODE}" == "switchover" ]]; then
  aws rds switchover-global-cluster \
    --global-cluster-identifier "${GLOBAL_CLUSTER}" \
    --target-db-cluster-identifier "${TARGET_ARN}" \
    --region "${AWS_REGION}" > /dev/null
else
  aws rds failover-global-cluster \
    --global-cluster-identifier "${GLOBAL_CLUSTER}" \
    --target-db-cluster-identifier "${TARGET_ARN}" \
    --allow-data-loss \
    --region "${AWS_REGION}" > /dev/null
fi
echo "Requested ${MODE}. Waiting up to ${WAIT}s for the writer role to move to ${TARGET_REGION}..."
echo ""

# --- Poll until the target becomes writer ---
while true; do
  NOW_WRITER=$(aws rds describe-global-clusters \
    --global-cluster-identifier "${GLOBAL_CLUSTER}" \
    --region "${AWS_REGION}" \
    --query "GlobalClusters[0].GlobalClusterMembers[?IsWriter].DBClusterArn | [0]" \
    --output text 2>/dev/null || true)

  echo "  $(date +%H:%M:%S) — writer: ${NOW_WRITER}"

  if [[ "${NOW_WRITER}" == "${TARGET_ARN}" ]]; then
    ELAPSED=$(($(date +%s) - START))
    echo ""
    echo "RESULT: PASS — ${TARGET_REGION} is now the writer (~${ELAPSED}s)."
    echo "Global writer endpoint now points to ${TARGET_REGION}."
    exit 0
  fi

  if [[ $(($(date +%s) - START)) -ge ${WAIT} ]]; then
    echo ""
    echo "RESULT: FAIL — writer did not move to ${TARGET_REGION} within ${WAIT}s."
    exit 1
  fi

  sleep 15
done
