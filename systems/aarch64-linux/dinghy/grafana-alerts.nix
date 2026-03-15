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
            parseMode = "Markdown";
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
              noDataState = "Alerting";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    expr = "smartctl_device_smart_status";
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
              annotations.summary = "🚨 *SMART Drive Failure*\nNode: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Unknown{{ end }}\nDevice: {{ if $labels.device }}{{ $labels.device }}{{ else }}Unknown{{ end }}\nStatus: *FAILING*";
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
                    expr = "up";
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
              annotations.summary = "💀 *Node Offline*\nNode: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Unknown{{ end }}\nStatus: *DOWN* for > 3 minutes";
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
              annotations.summary = "❌ *Systemd Service Failed*\nNode: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Unknown{{ end }}\nService: {{ if $labels.name }}{{ $labels.name }}{{ else }}Unknown{{ end }}";
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
              annotations.summary = "🔥 *High CPU Usage*\nNode: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Unknown{{ end }}\nLoad: *{{ if $values.B }}{{ $values.B | printf \"%.1f\" }}%{{ else }}N/A{{ end }}*";
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
              annotations.summary = "🧠 *High RAM Usage*\nNode: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Unknown{{ end }}\nUsage: *{{ if $values.B }}{{ $values.B | printf \"%.1f\" }}%{{ else }}N/A{{ end }}*";
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
              annotations.summary = "💾 *Storage Near Capacity*\nNode: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Unknown{{ end }}\nMountpoint: {{ if $labels.mountpoint }}{{ $labels.mountpoint }}{{ else }}Unknown{{ end }}\nUsage: *{{ if $values.B }}{{ $values.B | printf \"%.1f\" }}%{{ else }}N/A{{ end }}*";
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
              condition = "B";
              noDataState = "OK";
              execErrState = "Error";
              data = [
                {
                  refId = "A";
                  datasourceUid = "prometheus_ds";
                  relativeTimeRange = { from = 600; to = 0; };
                  model = {
                    expr = "vector(1)";
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
              ];
              for = "0m"; 
              labels.report = "daily";
              annotations.summary = "✅ *Daily All-Clear*\nInfrastructure is operating normally. All monitored SMART drives report passing health.";
            }
          ];
        }
      ];
    };
  };
}
