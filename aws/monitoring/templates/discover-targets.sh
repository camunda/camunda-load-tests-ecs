#!/bin/sh
# Discover orchestration-cluster targets from AWS Cloud Map namespaces.
# Writes a Prometheus file_sd_configs JSON file that is hot-reloaded.
#
# Uses the AWS Cloud Map API (servicediscovery) to find all private DNS
# namespaces ending in "-oc.service.local", then lists registered instances
# to get IP addresses directly — no DNS resolution tools (dig/nslookup) needed.
#
# NOTE: Do NOT use "set -e" — this is a long-running sidecar loop and a
# transient AWS API failure must not kill the container (and with it the
# entire Fargate task, since the container is marked essential).

TARGETS_FILE="${TARGETS_FILE:-/etc/prometheus/targets/benchmarks.json}"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-30}"
PORT="${PORT:-9600}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
TMPDIR="${TMPDIR:-/tmp}"

mkdir -p "$(dirname "$TARGETS_FILE")"

# Write an empty targets file immediately so Prometheus can start cleanly
echo "[]" > "$TARGETS_FILE"

while true; do
  echo "--- Discovery cycle starting ---"
  echo "Region: ${AWS_DEFAULT_REGION:-<not set>}, Environment: ${ENVIRONMENT}"

  # Step 1: Get all private DNS namespace IDs and Names
  # --output text gives tab-separated: "ns-xxx\tname.service.local" per line
  NS_FILE="${TMPDIR}/namespaces.txt"
  if ! aws servicediscovery list-namespaces \
    --filters Name=TYPE,Values=DNS_PRIVATE \
    --query 'Namespaces[].[Id,Name]' --output text > "$NS_FILE" 2>"${TMPDIR}/ns-error.txt"; then
    echo "ERROR: list-namespaces failed: $(cat "${TMPDIR}/ns-error.txt")"
  fi
  NS_COUNT=$(wc -l < "$NS_FILE" | tr -d ' ')
  echo "Found ${NS_COUNT} private DNS namespace(s)"

  # Step 2: Build the targets JSON
  TARGETS="["
  FIRST=true

  # Remove "None" lines from AWS CLI output (returned when query matches nothing)
  sed -i '/^None$/d' "$NS_FILE"

  # Read namespace file line by line (no subshell piping)
  while IFS="	" read -r NS_ID NS_NAME; do
    # Skip empty lines
    [ -z "$NS_ID" ] && continue

    # Match only orchestration-cluster namespaces (ending in -oc.service.local)
    case "$NS_NAME" in
      *-oc.service.local) ;;
      *) continue ;;
    esac

    # Filter by environment:
    #   dev  → only namespaces starting with "dev-"
    #   prod → only namespaces that do NOT start with "dev-"
    if [ "$ENVIRONMENT" = "dev" ]; then
      case "$NS_NAME" in
        dev-*) ;;
        *) continue ;;
      esac
    else
      case "$NS_NAME" in
        dev-*) continue ;;
      esac
    fi

    echo "  Checking namespace: ${NS_NAME} (${NS_ID})"

    # Find the "orchestration-cluster" service in this namespace
    SVC_ID=$(aws servicediscovery list-services \
      --filters Name=NAMESPACE_ID,Values="$NS_ID" \
      --query "Services[?Name=='orchestration-cluster'].Id | [0]" \
      --output text 2>/dev/null || echo "None")

    if [ -z "$SVC_ID" ] || [ "$SVC_ID" = "None" ]; then
      echo "    No orchestration-cluster service found, skipping"
      continue
    fi

    echo "    Found service: ${SVC_ID}"

    # List all registered instances — get IPs and ECS task IDs from Cloud Map.
    # Each instance is registered by ECS with InstanceId = task-id and
    # Attributes containing AWS_INSTANCE_IPV4.
    # Output format (tab-separated): "task-id  ip-address" per line
    INSTANCES_FILE="${TMPDIR}/instances.txt"
    aws servicediscovery list-instances \
      --service-id "$SVC_ID" \
      --query 'Instances[].[Id,Attributes.AWS_INSTANCE_IPV4]' \
      --output text > "$INSTANCES_FILE" 2>/dev/null || true

    INSTANCE_COUNT=$(grep -c . "$INSTANCES_FILE" 2>/dev/null || echo "0")
    if [ "$INSTANCE_COUNT" -eq 0 ] || [ "$(cat "$INSTANCES_FILE")" = "None" ]; then
      echo "    No instances registered, skipping"
      continue
    fi

    # Extract benchmark name: "benchmark1-oc.service.local" -> "benchmark1-oc"
    BENCHMARK=$(echo "$NS_NAME" | sed 's/\.service\.local$//')

    echo "    Discovered ${INSTANCE_COUNT} instance(s) for ${BENCHMARK}"

    # Emit one target group per instance so each gets its own "pod" label
    # (the ECS task ID). This lets Prometheus distinguish individual tasks.
    while IFS="	" read -r TASK_ID IP; do
      [ -z "$IP" ] || [ "$IP" = "None" ] && continue

      # Shorten the task ID: strip any ARN prefix, keep just the ID suffix
      # e.g. "arn:aws:ecs:…:task/cluster/abc123def" -> "abc123def"
      #      "abc123def" -> "abc123def" (already short)
      SHORT_TASK_ID=$(echo "$TASK_ID" | sed 's|.*/||')

      if [ "$FIRST" = true ]; then
        FIRST=false
      else
        TARGETS="${TARGETS},"
      fi

      TARGETS="${TARGETS}
  {
    \"targets\": [\"${IP}:${PORT}\"],
    \"labels\": {
      \"namespace\": \"ecs-${BENCHMARK}\",
      \"cluster\": \"ecs\",
      \"pod\": \"${SHORT_TASK_ID}\",
      \"__metrics_path__\": \"/actuator/prometheus\"
    }
  }"
    done < "$INSTANCES_FILE"
  done < "$NS_FILE"

  TARGETS="${TARGETS}
]"

  echo "Targets JSON: ${TARGETS}"

  # Atomic write: write to temp file then move
  echo "$TARGETS" > "${TARGETS_FILE}.tmp"
  mv "${TARGETS_FILE}.tmp" "$TARGETS_FILE"

  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Targets written to ${TARGETS_FILE}"
  sleep "$REFRESH_INTERVAL"
done
