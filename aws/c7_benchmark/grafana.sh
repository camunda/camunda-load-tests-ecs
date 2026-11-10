#!/bin/bash
# Local Grafana with the C7 dashboard on top of the ECS monitoring Prometheus.
#
# The ECS monitoring layer has Prometheus but no Grafana, and Prometheus is only reachable inside
# the VPC. This forwards it to localhost through ECS Exec (SSM) on the running engine task, then
# starts Grafana on http://localhost:3001 with the C7 dashboard from camunda/camunda
# (load-tests/c7/monitor/grafana, ref DASHBOARD_REF, default main).
#
# Requires: aws CLI v2, session-manager-plugin, docker, curl.
#   ./grafana.sh dev-c7-1            # prefix of the benchmark
set -euo pipefail
PREFIX="${1:?usage: grafana.sh <prefix> [ecs-cluster]}"
CLUSTER="${2:-camunda-dev-cluster}"
ENV="${PREFIX%%-*}"
PROM_HOST="prometheus.${ENV}-monitoring.service.local"
LOCAL_PORT="${LOCAL_PORT:-19090}"
DASHBOARD_REF="${DASHBOARD_REF:-main}"
DASHBOARD_URL="https://raw.githubusercontent.com/camunda/camunda/${DASHBOARD_REF}/load-tests/c7/monitor/grafana/c7-benchmark.json"

task=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$PREFIX-c7-engine" --query 'taskArns[0]' --output text)
task_id="${task##*/}"
runtime=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$task" --query 'tasks[0].containers[0].runtimeId' --output text)
target="ecs:${CLUSTER}_${task_id}_${runtime}"

echo "Forwarding $PROM_HOST:9090 -> localhost:$LOCAL_PORT via $target"
aws ssm start-session --target "$target" --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$PROM_HOST\"],\"portNumber\":[\"9090\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" &
forward_pid=$!
trap 'kill $forward_pid 2>/dev/null; docker rm -f c7-ecs-grafana >/dev/null 2>&1' EXIT

provisioning=$(mktemp -d)
mkdir -p "$provisioning/datasources" "$provisioning/dashboards" "$provisioning/json"
curl -fsSL "$DASHBOARD_URL" -o "$provisioning/json/c7-benchmark.json"
cat > "$provisioning/datasources/prometheus.yml" <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    url: http://host.docker.internal:$LOCAL_PORT
    isDefault: true
EOF
cat > "$provisioning/dashboards/dashboards.yml" <<EOF
apiVersion: 1
providers:
  - name: c7-benchmark
    type: file
    options:
      path: /etc/grafana/provisioning/json
EOF

docker run --rm --name c7-ecs-grafana -p 3001:3000 \
  -e GF_AUTH_ANONYMOUS_ENABLED=true -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin -e GF_AUTH_DISABLE_LOGIN_FORM=true \
  --add-host host.docker.internal:host-gateway \
  -v "$provisioning":/etc/grafana/provisioning:ro \
  grafana/grafana:12.1.1 &
echo "Grafana: http://localhost:3001/d/c7-benchmark?var-namespace=ecs-$PREFIX-c7  (Ctrl-C to stop)"
wait
