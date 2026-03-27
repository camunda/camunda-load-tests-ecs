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

