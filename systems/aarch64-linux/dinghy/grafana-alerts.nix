{
  config,
  lib,
  pkgs,
  ...
}:

let

  # Define groups with testScenarios separately to avoid Grafana schema errors
  myGroups = [
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
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
              model = {
                expr = "max by (instance, device) (smartmon_device_smart_healthy) == 0 and on(instance) up{job=\"nodes\"} == 1";
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
          annotations.summary = "🚨 Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Resolved{{ end }}\nDevice: {{ if $labels.device }}{{ $labels.device }}{{ else }}Clean{{ end }}\nStatus: <b>{{ if $labels.instance }}FAILING{{ else }}OK{{ end }}</b>";
          testScenarios = {
            "smart_drive_failure" = {
              metric = "smartmon_device_smart_healthy";
              labels = {
                device = "/dev/test-nvme";
              };
              value = 0;
            };
          };
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
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
              model = {
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
          annotations.summary = "💀 Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Resolved{{ end }}\nStatus: <b>{{ if $labels.instance }}DOWN{{ else }}UP{{ end }}</b>";
          testScenarios = {
            "node_down" = {
              metric = "up";
              labels = {
                job = "nodes";
              };
              value = 0;
            };
          };
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
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
              model = {
                expr = "max by (instance, job) (up{job!~\"nodes|self\", instance!~\"cargohold:.*\"}) == 0 and on(instance) up{job=\"nodes\"} == 1";
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
          testScenarios = {
            "exporter_scrape_failed" = {
              metric = "up";
              labels = {
                job = "test-exporter";
              };
              value = 0;
            };
          };
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
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
              model = {
                expr = "max by (instance, name) (node_systemd_unit_state{state=\"failed\"})";
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
          annotations.summary = "❌ Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Resolved{{ end }}\nService: {{ if $labels.name }}{{ $labels.name }}{{ else }}Clean{{ end }}";
          testScenarios = {
            "systemd_service_failed" = {
              metric = "node_systemd_unit_state";
              labels = {
                name = "test-service.service";
                state = "failed";
              };
              value = 1;
            };
          };
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
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
              model = {
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
          annotations.summary = "🗄️ Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Resolved{{ end }}\nDevice: {{ if $labels.device }}{{ $labels.device }}{{ else }}Clean{{ end }} ({{ if $labels.label }}{{ $labels.label }}{{ else }}N/A{{ end }})\nState: <b>{{ if $labels.state }}{{ $labels.state }}{{ else }}N/A{{ end }}</b>\nUUID: <code>{{ if $labels.uuid }}{{ $labels.uuid }}{{ else }}N/A{{ end }}</code>";
          testScenarios = {
            "evacuating_drive" = {
              metric = "node_bcachefs_device_info";
              labels = {
                device = "99";
                label = "test-hdd";
                state = "evacuating";
                uuid = "test-uuid";
              };
              value = 1;
            };
          };
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
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
              model = {
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
          annotations.summary = "💾 Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Resolved{{ end }}\nPool UUID: <code>{{ if $labels.uuid }}{{ $labels.uuid }}{{ else }}N/A{{ end }}</code>\n<i>One or more drives have likely dropped from the OS.</i>";
          testScenarios = {
            "bcachefs_device_missing" = {
              metric = "node_bcachefs_device_info";
              labels = {
                uuid = "missing-pool-uuid";
                device = "1";
                state = "missing";
              };
              value = 1;
            };
          };
        }
        {
          uid = "bcachefs_data_corruption";
          title = "Bcachefs Data Corruption";
          condition = "C";
          noDataState = "OK";
          execErrState = "Error";
          data = [
            {
              refId = "A";
              datasourceUid = "prometheus_ds";
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
              model = {
                expr = "rate(node_bcachefs_checksum_error_total[5m]) > 0 and on(instance) up{job=\"nodes\"} == 1";
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
          for = "0m";
          labels.severity = "critical";
          annotations.summary = "🧬 Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Resolved{{ end }}\nUUID: <code>{{ if $labels.uuid }}{{ $labels.uuid }}{{ else }}N/A{{ end }}</code>\n<i>Checksum errors are increasing. Data corruption has been detected!</i>";
          testScenarios = {
            "bcachefs_corruption" = {
              metric = "node_bcachefs_checksum_error_total";
              labels = {
                uuid = "test-fs-uuid";
              };
              value = 100;
            };
          };
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
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
              model = {
                # Join with filesystem info to find the 'root' device and filter out non-boot drives
                # Regex handles both /dev/sda1 -> sda and /dev/nvme0n1p3 -> nvme0n1
                expr = ''
                  (rate(node_disk_io_time_seconds_total{device!~"loop.*|ram.*|dm-.*"}[5m]) * 100 > 90)
                  and on(instance, device)
                  label_replace(node_filesystem_size_bytes{mountpoint="/"}, "device", "$1", "device", "/dev/([a-z]+[0-9]*[a-z]*[0-9]*).*")
                '';
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
          annotations.summary = "💽 Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Resolved{{ end }}\nDevice: <b>{{ if $labels.device }}{{ $labels.device }}{{ else }}Clean{{ end }}</b>\nSaturation: <b>{{ if $values.B }}{{ $values.B.Value | printf \"%.1f\" }}%{{ else }}N/A{{ end }}</b>\n<i>The boot disk is saturated. This can cause system latency.</i>";
          testScenarios = {
            "disk_saturation" = {
              metric = "node_disk_io_time_seconds_total";
              labels = {
                device = "sda";
              };
              value = 1000;
            };
          };
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
              relativeTimeRange = {
                from = 900;
                to = 0;
              };
              model = {
                expr = "(1 - avg by(instance)(rate(node_cpu_seconds_total{mode=\"idle\",instance!=\"dinghy\"}[15m]))) * 100";
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
          for = "15m";
          labels.severity = "warning";
          annotations.summary = "🔥 Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Unknown{{ end }}\nLoad: <b>{{ if $values.B }}{{ $values.B.Value | printf \"%.1f\" }}%{{ else }}N/A{{ end }}</b>";
          testScenarios = {
            "high_cpu" = {
              metric = "node_cpu_seconds_total";
              labels = {
                mode = "user";
                cpu = "0";
              };
              value = 5000;
            };
          };
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
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
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
          testScenarios = {
            "high_ram" = {
              metric = "node_memory_MemAvailable_bytes";
              labels = { };
              value = 0;
            };
          };
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
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
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
          annotations.summary = "💾 Node: {{ if $labels.instance }}{{ $labels.instance }}{{ else }}Resolved{{ end }}\nMountpoint: {{ if $labels.mountpoint }}{{ $labels.mountpoint }}{{ else }}Unknown{{ end }}\nUsage: <b>{{ if $values.B }}{{ $values.B.Value | printf \"%.1f\" }}%{{ else }}N/A{{ end }}</b>";
          testScenarios = {
            "storage_full" = {
              metric = "node_filesystem_free_bytes";
              labels = {
                mountpoint = "/";
                fstype = "ext4";
              };
              value = 0;
            };
          };
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
          condition = "A_red";
          noDataState = "OK";
          execErrState = "Error";
          data = [
            {
              refId = "A";
              datasourceUid = "prometheus_ds";
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
              model = {
                # Fires at 8:00 AM UTC OR when test_daily_report is 1
                expr = "(vector(1) * ((time() % 86400 >= bool 28800) * (time() % 86400 < bool 29100))) or (test_daily_report == 1)";
                refId = "A";
              };
            }
            {
              refId = "A_red";
              datasourceUid = "__expr__";
              model = {
                expression = "A";
                type = "reduce";
                reducer = "last";
                refId = "A_red";
              };
            }
            {
              refId = "B";
              datasourceUid = "prometheus_ds";
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
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
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
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
              relativeTimeRange = {
                from = 600;
                to = 0;
              };
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
            {{ if and (eq $values.B_red.Value 0.0) (eq $values.C_red.Value 0.0) (eq $values.D_red.Value 0.0) -}}
            ✅ <b>Daily All-Clear</b>
            Infrastructure is operating normally. All systems are healthy.
            {{- else -}}
            ⚠️ <b>Daily Health Summary: Issues Found</b>
            {{ if gt $values.B_red.Value 0.0 }}- Offline Nodes: <b>{{ $values.B_red.Value | printf "%.0f" }}</b>{{ end }}
            {{ if gt $values.C_red.Value 0.0 }}- Unhealthy Bcachefs: <b>{{ $values.C_red.Value | printf "%.0f" }}</b>{{ end }}
            {{ if gt $values.D_red.Value 0.0 }}- SMART Failures: <b>{{ $values.D_red.Value | printf "%.0f" }}</b>{{ end }}
            {{- end -}}
          '';
          testScenarios = {
            "daily_report_trigger" = {
              metric = "test_daily_report";
              labels = { };
              value = 1;
            };
          };
        }
      ];
    }
  ];

  # Strip testScenarios for Grafana provisioning
  grafanaGroups = map (
    group:
    group
    // {
      rules = map (rule: builtins.removeAttrs rule [ "testScenarios" ]) group.rules;
    }
  ) myGroups;

  # Extract testScenarios for alert-test JSON
  allRules = lib.flatten (map (group: group.rules) myGroups);
  scenarios = lib.foldl' (
    acc: rule: if rule ? testScenarios then acc // rule.testScenarios else acc
  ) { } allRules;

in
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
                    {{- range $index, $alert := .Alerts -}}
                      {{- if gt $index 0 }}

      ---------------------------------------

      {{ end -}}
                      {{- if eq .Status "firing" -}}
                        {{- if eq .Labels.report "daily" -}}
                          {{ .Annotations.summary }}
                        {{- else -}}
                          <b>🔥 ALARM 🔥: {{ .Labels.alertname }}</b>
      {{ .Annotations.summary }}
                        {{- end -}}
                      {{- else -}}
                        {{- if ne .Labels.report "daily" -}}
                          <b>✅ RESOLVED: {{ .Labels.alertname }}</b>
      {{ .Annotations.summary }}
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
              group_by = [ "alertname" "instance" "device" "name" ];
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
      policies = [
        {
          orgId = 1;
          receiver = "Telegram-Critical-And-Reports-Manual";
          group_by = [
            "alertname"
            "instance"
            "device"
            "name"
          ];
          routes = [
            {
              receiver = "Telegram-Critical-And-Reports-Manual";
              object_matchers = [
                [
                  "severity"
                  "="
                  "critical"
                ]
              ];
              group_wait = "0s";
              repeat_interval = "1h";
            }
            {
              receiver = "Telegram-Critical-And-Reports-Manual";
              object_matchers = [
                [
                  "report"
                  "="
                  "daily"
                ]
              ];
              group_wait = "0s";
              repeat_interval = "24h";
            }
          ];
        }
      ];
    };

    rules.settings = {
      apiVersion = 1;
      groups = grafanaGroups;
    };
  };

  # 4. Generate the scenarios.json for alert-test
  environment.etc."infra-test/scenarios.json" = lib.mkIf config.services.grafana.enable {
    text = builtins.toJSON scenarios;
  };
}
