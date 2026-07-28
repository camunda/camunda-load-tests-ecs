#!/usr/bin/env bash
#
# region-disconnect-create.sh
#
# Creates an FIS experiment template that simulates a full region failure by
# disrupting ALL network connectivity on every private subnet in the target
# region's VPC. Uses the `aws:network:disrupt-connectivity` action with
# scope=all, which clones the subnets' network ACLs and adds deny-all rules,
# then restores them when the duration expires.
#
# In the dual-region setup, the two regions communicate over VPC peering.
# Isolating every private subnet in region_1 (us-east-1) therefore severs the
# cross-region link and cuts the region_1 brokers off from region_0 — the
# region looks "gone" from the primary's point of view. Cross-region Raft
# partitions lose quorum for the duration; the test is whether the cluster
# heals once connectivity is restored.
#
# Reuses the existing FIS-Experiment-Role NACL permissions — no IAM change.
#
# Prerequisites:
#   - FIS-Admin role assumed (source ./experiments/assume-fis-role.sh)
#   - Setup scripts have been run
#   - dual-region infra/app deployed (region_1 VPC + ECS exist)
#
# Usage:
#   ./experiments/region-disconnect/region-disconnect-create.sh --duration PT10M
#   ./experiments/region-disconnect/region-disconnect-create.sh --region us-east-1 --vpc camunda-us-east-1-vpc --duration PT15M
#
# Options:
#   --region    Target region to isolate (default: us-east-1 = region_1/secondary)
#   --vpc       VPC name tag to find subnets (default: camunda-us-east-1-vpc)
#   --duration  Disruption duration in ISO 8601 (default: PT10M)
#   --name      Experiment template name tag (default: 6-region-disconnect-dev)
#   --log-group CloudWatch log group (default: /fis/chaos-tests)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# --- Defaults ---
# NOTE: the target region is us-east-1 (region_1). AWS_REGION is set to the
# target so the FIS template is created in the same region it acts on.
AWS_REGION="${AWS_REGION:-us-east-1}"
FIS_EXPERIMENT_ROLE="${FIS_EXPERIMENT_ROLE:-FIS-Experiment-Role}"
VPC_NAME="${VPC_NAME:-camunda-us-east-1-vpc}"
DURATION="PT10M"
TEMPLATE_NAME="6-region-disconnect-dev"
LOG_GROUP="${FIS_LOG_GROUP:-/fis/chaos-tests}"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)    AWS_REGION="$2";    shift 2 ;;
    --vpc)       VPC_NAME="$2";      shift 2 ;;
    --duration)  DURATION="$2";      shift 2 ;;
    --name)      TEMPLATE_NAME="$2"; shift 2 ;;
    --log-group) LOG_GROUP="$2";     shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--region <REGION>] [--vpc <VPC_NAME>] [--duration <ISO8601>] [--name <NAME>]"
      echo ""
      echo "Options:"
      echo "  --region    Target region to isolate (default: us-east-1)"
      echo "  --vpc       VPC name tag (default: camunda-us-east-1-vpc)"
      echo "  --duration  Disruption duration in ISO 8601 (default: PT10M)"
      echo "  --name      Experiment template name tag (default: 6-region-disconnect-dev)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "=== Creating Region Disconnect Experiment Template ==="
echo "Target region: ${AWS_REGION}"
echo "VPC:           ${VPC_NAME}"
echo "Duration:      ${DURATION}"
echo "Template name: ${TEMPLATE_NAME}"
echo ""

# --- Get account ID ---
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: ${ACCOUNT_ID}"

# --- Find VPC ID ---
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query "Vpcs[0].VpcId" \
  --output text \
  --region "${AWS_REGION}")

if [[ -z "${VPC_ID}" || "${VPC_ID}" == "None" ]]; then
  echo "ERROR: VPC '${VPC_NAME}' not found in ${AWS_REGION}"
  exit 1
fi
echo "VPC ID: ${VPC_ID}"

# --- Find ALL private subnets in the VPC (every AZ) ---
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "Subnets[?!MapPublicIpOnLaunch].SubnetId" \
  --output text \
  --region "${AWS_REGION}")

if [[ -z "${SUBNET_IDS}" || "${SUBNET_IDS}" == "None" ]]; then
  echo "ERROR: No private subnets found in VPC '${VPC_ID}'"
  exit 1
fi

echo "Target private subnets (whole region):"

# Build the resource ARNs array
RESOURCE_ARNS=""
for SUBNET_ID in ${SUBNET_IDS}; do
  echo "  - ${SUBNET_ID}"
  if [[ -n "${RESOURCE_ARNS}" ]]; then
    RESOURCE_ARNS="${RESOURCE_ARNS},"
  fi
  RESOURCE_ARNS="${RESOURCE_ARNS}\"arn:aws:ec2:${AWS_REGION}:${ACCOUNT_ID}:subnet/${SUBNET_ID}\""
done

echo ""

# --- Ensure CloudWatch log group exists ---
ensure_log_group "${LOG_GROUP}"

# --- Build and create the experiment template ---
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${FIS_EXPERIMENT_ROLE}"
LOG_GROUP_ARN="arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"

cat > /tmp/fis-experiment-template.json << EOF
{
  "description": "Disconnect region ${AWS_REGION} - isolate ALL private subnets (full region failure) for ${DURATION}",
  "targets": {
    "target-subnets": {
      "resourceType": "aws:ec2:subnet",
      "resourceArns": [${RESOURCE_ARNS}],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "disconnect-region": {
      "actionId": "aws:network:disrupt-connectivity",
      "parameters": {
        "scope": "all",
        "duration": "${DURATION}"
      },
      "targets": {
        "Subnets": "target-subnets"
      }
    }
  },
  "stopConditions": [
    {
      "source": "none"
    }
  ],
  "logConfiguration": {
    "cloudWatchLogsConfiguration": {
      "logGroupArn": "${LOG_GROUP_ARN}"
    },
    "logSchemaVersion": 2
  },
  "roleArn": "${ROLE_ARN}",
  "tags": {
    "Name": "${TEMPLATE_NAME}",
    "target_region": "${AWS_REGION}",
    "duration": "${DURATION}",
    "environment": "dev",
    "managed_by": "chaos-tests",
    "repository": "camunda/zeebe-terraform"
  }
}
EOF

# --- Delete existing template and create new one ---
delete_template_by_name "${TEMPLATE_NAME}"
create_template /tmp/fis-experiment-template.json

echo ""
echo "=== Experiment template created ==="
echo "Template ID: ${TEMPLATE_ID}"
echo "Name:        ${TEMPLATE_NAME}"
echo ""
echo "To run the experiment (health endpoint = region_0 primary ALB, over VPN):"
echo "  ./experiments/region-disconnect/region-disconnect-run.sh --name ${TEMPLATE_NAME} --endpoint <REGION_0_ALB_DNS>"
