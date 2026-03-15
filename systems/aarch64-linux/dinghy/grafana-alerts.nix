{ config, lib, pkgs, ... }:

{
  # 1. Point Grafana to the SOPS Secret as an EnvironmentFile
  sops.secrets.grafana_telegram_env.owner = "grafana";

  systemd.services.grafana.serviceConfig.EnvironmentFile = [
    config.sops.secrets.grafana_telegram_env.path
  ];

  # 2. Enable Grafana Provisioning
  services.grafana.provision.enable = true;

  # 3. Grafana Alerting Provisioning
  services.grafana.provision.alerting = {
# FIXME: this needs to be removed after grafana bug is fixed for contactPoints 
    # Commented out due to numeric Chat ID bug in Telegram integration
    /*
    contactPoints.settings = {
      apiVersion = 1;
      contactPoints = [{
        orgId = 1;
        name = "Telegram-Critical-And-Reports";
        receivers = [{
          uid = "telegram_1";
          type = "telegram";
          settings = {
            bottoken = "$__env{TELEGRAM_BOT_TOKEN}";
            chatid = "$__env{TELEGRAM_CHAT_ID}";
            parseMode = "HTML";
            message = ''
              {{- range .Alerts -}}
                {{- if eq .Status "firing" -}}
                  {{- if eq .Labels.report "daily" -}}
                    {{ .Annotations.summary }}
                  {{- else -}}
                    <b>🔥 ALARM 🔥: {{ .Labels.alertname }}</b>
                    {{- if .Annotations.summary }}
                    {{ .Annotations.summary }}
                    {{- end }}
                  {{- end -}}
                {{- else -}}
                  {{- if ne .Labels.report "daily" -}}
                    <b>✅ RESOLVED: {{ .Labels.alertname }}</b>
                    {{- if .Annotations.summary }}
                    {{ .Annotations.summary }}
                    {{- end }}
                  {{- end -}}
                {{- end -}}
              {{- end -}}
            '';
          };
        }];
      }];
    };

    policies.settings = {
      apiVersion = 1;
      policies = [{
        orgId = 1;
        receiver = "Telegram-Critical-And-Reports";
        group_by = [ "alertname" "instance" ];
        routes = [
          {
            receiver = "Telegram-Critical-And-Reports";
            object_matchers = [ ["severity" "=" "critical"] ];
            group_wait = "0s";
            repeat_interval = "1h";
          }
          {
            receiver = "Telegram-Critical-And-Reports";
            object_matchers = [ ["report" "=" "daily"] ];
            group_wait = "0s";
            repeat_interval = "24h";
          }
        ];
      }];
    };
*/
# FIXME: this needs to be removed after grafana bug is fixed for contactPoints 
    policies.settings = {
      apiVersion = 1;
      policies = [{
        orgId = 1;
        receiver = "Telegram-Critical-And-Reports-Manual";
        group_by = [ "alertname" "instance" ];
        routes = [
          {
            receiver = "Telegram-Critical-And-Reports-Manual";
            object_matchers = [ ["severity" "=" "critical"] ];
            group_wait = "0s";
            repeat_interval = "1h";
          }
          {
            receiver = "Telegram-Critical-And-Reports-Manual";
            object_matchers = [ ["report" "=" "daily"] ];
            group_wait = "0s";
            repeat_interval = "24h";
          }
        ];
      }];
    };
    

    rules.settings = {
      apiVersion = 1;
      groups = [
        {
          name = "Hardware and Node Failures";
          folder = "Infrastructure";
          interval = "1m";
          rules = [
            {
              uid = "smart_drive_failure";
              title = "SMART Drive Failure";
              condition = "C";
              noDataState = "OK";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    expr = "smartmon_device_smart_healthy == 0 and on(instance) up{job=\"nodes\"} == 1";
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "A";
                    type = "reduce";
                    reducer = "last";
                    refId = "B";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "$B < 1";
                    type = "math";
                    refId = "C";
                  };
                }
              ];
              for = "1m";
              labels.severity = "critical";
              annotations.summary = "🚨 Node: {{ $labels.instance }}\nDevice: {{ $labels.device }}\nStatus: <b>FAILING</b>";
            }
            {
              uid = "node_down";
              title = "Node Down";
              condition = "C";
              noDataState = "Alerting";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    # This targets the primary node_exporter, which we use as the source of truth for "is the host up?"
                    expr = "up{job=\"nodes\", instance!~\"cargohold:.*\"}";
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "A";
                    type = "reduce";
                    reducer = "last";
                    refId = "B";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "$B == 0";
                    type = "math";
                    refId = "C";
                  };
                }
              ];
              for = "3m"; 
              labels.severity = "critical";
              annotations.summary = "💀 Node: {{ $labels.instance }}\nStatus: <b>DOWN</b> for > 3 minutes";
            }
            {
              uid = "exporter_scrape_failed";
              title = "Exporter Scrape Failed";
              condition = "C";
              noDataState = "OK";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    # Targets secondary exporters (smart-devices, etc.)
                    # We only alert if the main node is still online to avoid double-alerting during a full outage.
                    expr = "up{job!~\"nodes|self\", instance!~\"cargohold:.*\"} == 0 and on(instance) up{job=\"nodes\"} == 1";
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "A";
                    type = "reduce";
                    reducer = "last";
                    refId = "B";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "$B > 0";
                    type = "math";
                    refId = "C";
                  };
                }
              ];
              for = "5m"; 
              labels.severity = "warning";
              annotations.summary = "⚠️ Node: {{ $labels.instance }}\nJob: <b>{{ $labels.job }}</b>\n<i>The exporter on this node is not responding, but the node itself is still online.</i>";
            }
            {
              uid = "systemd_service_failed";
              title = "Systemd Service Failed";
              condition = "C";
              noDataState = "OK";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    expr = "node_systemd_unit_state{state=\"failed\"}";
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "A";
                    type = "reduce";
                    reducer = "last";
                    refId = "B";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "$B > 0";
                    type = "math";
                    refId = "C";
                  };
                }
              ];
              for = "2m";
              labels.severity = "critical";
              annotations.summary = "❌ Node: {{ $labels.instance }}\nService: {{ $labels.name }}";
            }
          ];
        }
        {
          name = "Storage Health";
          folder = "Infrastructure";
          interval = "1m";
          rules = [
            {
              uid = "bcachefs_device_unhealthy";
              title = "Bcachefs Device Unhealthy";
              condition = "C";
              noDataState = "OK";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    # A state is healthy if 'rw' is the active state (in brackets) or if it is exactly 'rw'.
                    # This allows transitional states like '[rw] ro evacuating spare' but alerts on 'rw ro [evacuating] spare'.
                    expr = "node_bcachefs_device_info{state!~\".*\\\\[rw\\\\].*|^rw$\"} and on(instance) up{job=\"nodes\"} == 1";
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "A";
                    type = "reduce";
                    reducer = "last";
                    refId = "B";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "$B > 0";
                    type = "math";
                    refId = "C";
                  };
                }
              ];
              for = "1m";
              labels.severity = "critical";
              annotations.summary = "🗄️ Node: {{ $labels.instance }}\nDevice: {{ $labels.device }} ({{ $labels.label }})\nState: <b>{{ $labels.state }}</b>\nUUID: <code>{{ $labels.uuid }}</code>";
            }
            {
              uid = "bcachefs_device_missing";
              title = "Bcachefs Device Missing";
              condition = "C";
              noDataState = "OK";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    # Compare current count with the maximum count seen in the last 24h
                    # This is more robust than doing the math in Grafana expressions.
                    # Only alert if the node is still up to avoid false positives during node downtime.
                    expr = "((count by (instance, uuid) (node_bcachefs_device_info)) < (max_over_time(count by (instance, uuid) (node_bcachefs_device_info)[24h:1m]))) and on(instance) up{job=\"nodes\"} == 1";
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "A";
                    type = "reduce";
                    reducer = "last";
                    refId = "B";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "$B > 0";
                    type = "math";
                    refId = "C";
                  };
                }
              ];
              for = "2m";
              labels.severity = "critical";
              annotations.summary = "💾 Node: {{ $labels.instance }}\nPool UUID: <code>{{ $labels.uuid }}</code>\n<i>One or more drives have likely dropped from the OS.</i>";
            }
            {
              uid = "high_disk_io_saturation";
              title = "High Disk IO Saturation";
              condition = "C";
              noDataState = "OK";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    # rate of io_time_seconds_total gives the fraction of time the disk was busy.
                    # 0.9 = 90% saturation. We ignore loop and ram devices.
                    expr = "rate(node_disk_io_time_seconds_total{device!~\"loop.*|ram.*\"}[5m]) > 0.9 and on(instance) up{job=\"nodes\"} == 1";
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "A";
                    type = "reduce";
                    reducer = "last";
                    refId = "B";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "$B > 0";
                    type = "math";
                    refId = "C";
                  };
                }
              ];
              for = "10m";
              labels.severity = "warning";
              annotations.summary = "💽 Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Unknown{{ end }}\nDevice: <b>{{ if $labels.device }}{{ $labels.device }}{{ else }}Unknown{{ end }}</b>\nSaturation: <b>{{ if $values.B }}{{ $values.B.Value | printf \"%.1f\" }}%{{ else }}N/A{{ end }}</b>\n<i>This disk is consistently saturated and may be causing system-wide latency.</i>";
              }
              ];
              }
        {
          name = "Resource Pressure";
          folder = "Infrastructure";
          interval = "2m";
          rules = [
            {
              uid = "high_cpu_load";
              title = "High CPU Load";
              condition = "C";
              noDataState = "OK";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    expr = "(1 - avg by(instance)(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))) * 100";
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "A";
                    type = "reduce";
                    reducer = "last";
                    refId = "B";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "$B > 90";
                    type = "math";
                    refId = "C";
                  };
                }
              ];
              for = "5m";
              labels.severity = "warning";
              annotations.summary = "🔥 Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Unknown{{ end }}\nLoad: <b>{{ if $values.B }}{{ $values.B.Value | printf \"%.1f\" }}%{{ else }}N/A{{ end }}</b>";
            }
            {
              uid = "high_ram_usage";
              title = "High RAM Usage";
              condition = "C";
              noDataState = "OK";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    expr = "((node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes) * 100";
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "A";
                    type = "reduce";
                    reducer = "last";
                    refId = "B";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "$B > 90";
                    type = "math";
                    refId = "C";
                  };
                }
              ];
              for = "5m";
              labels.severity = "warning";
              annotations.summary = "🧠 Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Unknown{{ end }}\nUsage: <b>{{ if $values.B }}{{ $values.B.Value | printf \"%.1f\" }}%{{ else }}N/A{{ end }}</b>";
            }
            {
              uid = "storage_near_capacity";
              title = "Storage Near Capacity";
              condition = "C";
              noDataState = "OK";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    expr = "(1 - (node_filesystem_free_bytes{fstype=~\"ext4|xfs|zfs|bcachefs|vfat\"} / node_filesystem_size_bytes{fstype=~\"ext4|xfs|zfs|bcachefs|vfat\"})) * 100";
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "A";
                    type = "reduce";
                    reducer = "last";
                    refId = "B";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "$B > 85";
                    type = "math";
                    refId = "C";
                  };
                }
              ];
              for = "10m";
              labels.severity = "warning";
              annotations.summary = "💾 Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Unknown{{ end }}\nMountpoint: {{ if $labels.mountpoint }}{{ $labels.mountpoint }}{{ else }}Unknown{{ end }}\nUsage: <b>{{ if $values.B }}{{ $values.B.Value | printf \"%.1f\" }}%{{ else }}N/A{{ end }}</b>";
            }
          ];
        }
        {
          name = "Daily Reports";
          folder = "Reports";
          interval = "1m";
          rules = [
            {
              uid = "daily_infra_health_summary";
              title = "Daily Infrastructure Health Summary";
              condition = "A";
              noDataState = "OK";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    # Trigger for 5 minutes every day at 08:00 UTC.
                    # We use scalar math with 'bool' and wrap in 'vector()' to make it fire as an alert.
                    expr = "vector(1) * ((time() % 86400 >= bool 28800) * (time() % 86400 < bool 29100)) > 0";
                    refId = "A";
                  };
                }
                {
                  refId = "B";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    expr = "count(up{job=\"nodes\"} == 0) or vector(0)";
                    refId = "B";
                  };
                }
                {
                  refId = "B_red";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "B";
                    type = "reduce";
                    reducer = "last";
                    refId = "B_red";
                  };
                }
                {
                  refId = "C";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    expr = "count(node_bcachefs_device_info{state!~\".*rw.*\"}) or vector(0)";
                    refId = "C";
                  };
                }
                {
                  refId = "C_red";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "C";
                    type = "reduce";
                    reducer = "last";
                    refId = "C_red";
                  };
                }
                {
                  refId = "D";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    expr = "count(smartmon_device_smart_healthy == 0) or vector(0)";
                    refId = "D";
                  };
                }
                {
                  refId = "D_red";
                  datasourceUid = "__expr__";
                  model = {
                    expression = "D";
                    type = "reduce";
                    reducer = "last";
                    refId = "D_red";
                  };
                }
              ];
              for = "0m"; 
              labels.report = "daily";
              annotations.summary = ''
                {{- if and (eq $values.B_red.Value 0.0) (eq $values.C_red.Value 0.0) (eq $values.D_red.Value 0.0) -}}
                ✅ <b>Daily All-Clear</b>
                Infrastructure is operating normally. All systems are healthy.
                {{- else -}}
                ⚠️ <b>Daily Health Summary: Issues Found</b>
                {{ if gt $values.B_red.Value 0.0 }}- Offline Nodes: <b>{{ $values.B_red.Value | printf "%.0f" }}</b>{{ end }}
                {{ if gt $values.C_red.Value 0.0 }}- Unhealthy Bcachefs: <b>{{ $values.C_red.Value | printf "%.0f" }}</b>{{ end }}
                {{ if gt $values.D_red.Value 0.0 }}- SMART Failures: <b>{{ $values.D_red.Value | printf "%.0f" }}</b>{{ end }}
                {{- end -}}
              '';
            }
          ];
        }
      ];
    };
  };
}
