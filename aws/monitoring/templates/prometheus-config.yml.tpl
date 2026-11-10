global:
  scrape_interval: 15s
  external_labels:
    cluster: ${prefix}
scrape_configs:
  - job_name: 'core'
    metrics_path: /actuator/prometheus
    # Dynamically discover all benchmark orchestration-cluster targets.
    # A sidecar container queries AWS Cloud Map for namespaces matching
    # *-oc.service.local and writes targets to this JSON file.
    # Prometheus hot-reloads when the file changes — no restart needed.
    file_sd_configs:
      - files:
          - /etc/prometheus/targets/benchmarks.json
        refresh_interval: 30s
  # C7 benchmarks (aws/c7_benchmark): engine, starter, workers, postgres-exporter.
  # Targets come from the same discovery sidecar (c7.json). PostgreSQL metrics get the
  # cnpg_ prefix so the C7 dashboard works for GKE (CNPG) and ECS (postgres-exporter).
  - job_name: 'c7'
    file_sd_configs:
      - files:
          - /etc/prometheus/targets/c7.json
        refresh_interval: 30s
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: "(c7_(table|db|wal|runtime|activity)_.*)"
        target_label: __name__
        replacement: "cnpg_$1"
