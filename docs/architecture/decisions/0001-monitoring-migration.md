# Monitoring Migration Strategy

**Date:** 2025-05-23
**Status:** Proposed

## Context

Currently, system health monitoring relies on a custom Python script (`health-reporter`) running on each node (`capstans`, `lightships`, `cargohold`). This script sends daily reports and alerts via Telegram.

**Pain Points:**
-   **Noise:** Daily reports from every node create alert fatigue.
-   **Decentralized:** Each node reports independently; no holistic view.
-   **Maintenance:** Custom script requires maintenance and manual updates.
-   **Limited History:** No time-series data for trending or analysis (only instantaneous snapshots).

## Decision

We will migrate to a centralized monitoring stack hosted on the Kubernetes cluster (`capstans`, `lightships`) using **Prometheus** for metrics and **Loki** for logs. **Grafana** will provide visualization, and **Alertmanager** will handle notification routing (Telegram).

This setup leverages the existing `kube-prometheus-stack` ecosystem for K8s nodes and extends it to monitor the non-K8s node (`cargohold`) via standard exporters.

## Architecture

### 1. Central Monitoring Hub (Kubernetes Cluster)
Hosted on `capstans` and `lightships` nodes.

-   **Prometheus**: Scrapes metrics from all nodes (K8s and non-K8s).
    -   Deployed via `kube-prometheus-stack` Helm chart.
    -   Retention: 30 days (configurable).
-   **Loki**: Aggregates logs from all nodes.
    -   Deployed via `loki-stack` or `loki` Helm chart.
-   **Alertmanager**: Dedupes, groups, and routes alerts to Telegram.
-   **Grafana**: Visualization dashboard for metrics and logs.

### 2. Kubernetes Nodes (`capstans`, `lightships`)
-   **Metrics**:
    -   `node-exporter` (DaemonSet) runs on every node, managed by Prometheus Operator.
    -   `smartctl-exporter` (DaemonSet) runs on every node to expose drive health metrics.
-   **Logs**:
    -   `promtail` (DaemonSet) ships container logs and host system logs (`/var/log/*`, systemd journal) to Loki.

### 3. Non-Kubernetes Node (`cargohold`)
This node acts as an external target.

-   **Metrics**:
    -   **Node Exporter**: Runs as a systemd service (already enabled in NixOS `suites.monitoring`). Exposed on port 9100.
    -   **Smartctl Exporter**: Runs as a systemd service (already enabled). Exposed on port 9633.
    -   **Prometheus Configuration**: The K8s Prometheus instance will be configured with a `static_configs` job to scrape `cargohold:9100` and `cargohold:9633`.
-   **Logs**:
    -   **Grafana Alloy** (or Promtail): Runs as a systemd service (already in `suites.monitoring` but needs configuration).
    -   Configured to push logs to the K8s Loki endpoint (NodePort or LoadBalancer IP).

## Alerting Strategy

We will implement specific alerting rules to replace the custom script's functionality with "actionable" alerts only.

### 1. Node Down
Detects if a node is unreachable or the exporter is down.

```yaml
- alert: InstanceDown
  expr: up{job="node-exporter"} == 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Instance {{ $labels.instance }} down"
    description: "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 5 minutes."
```

### 2. Filesystem Read-Only
Detects if a filesystem has remounted as read-only (often due to disk errors).

```yaml
- alert: FilesystemReadOnly
  expr: node_filesystem_readonly{mountpoint!~"/boot.*"} == 1
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Filesystem read-only on {{ $labels.instance }}"
    description: "The filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} is read-only."
```

### 3. Drive Failure
Detects S.M.A.R.T. health failures using metrics from `smartctl-exporter`.

```yaml
- alert: SmartDeviceFailure
  expr: smartmon_device_smart_healthy == 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Drive failure detected on {{ $labels.instance }}"
    description: "Device {{ $labels.disk }} on {{ $labels.instance }} has failed S.M.A.R.T. check."
```

## Migration Plan

1.  **Deploy K8s Stack**:
    -   Install `kube-prometheus-stack` and `loki` on the cluster.
    -   Verify basic dashboards (Node Exporter, K8s resources).

2.  **Connect `cargohold`**:
    -   Ensure `cargohold`'s firewall allows ingress on 9100/9633 from the K8s cluster subnet.
    -   Configure K8s Prometheus with a scrape config for `cargohold`.
    -   Configure `cargohold`'s `alloy` service to push logs to K8s Loki.

3.  **Configure Alerts**:
    -   Apply `PrometheusRule` manifests for the alerts defined above.
    -   Configure `AlertmanagerConfig` to send notifications to the Telegram channel.

4.  **Verification**:
    -   Simulate a node down event (stop `node_exporter` on a node).
    -   Verify Telegram alert reception.

5.  **Decommission**:
    -   Remove `health-reporter` module from `modules/nixos/hosts/*` and `suites/monitoring`.
    -   Disable the cron/timer for the python script.

## Notes
-   The existing `modules/nixos/services/monitoring` NixOS module can be reused for `cargohold`'s client-side setup (exporters + Alloy).
-   K8s nodes should rely on the Helm chart's DaemonSets rather than the NixOS systemd services to avoid conflicts and improve K8s integration.
