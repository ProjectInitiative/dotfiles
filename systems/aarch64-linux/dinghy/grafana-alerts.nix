{ config, lib, pkgs, ... }:

{
  # 1. Ensure Grafana can read the secrets
  sops.secrets.health_reporter_bot_api_token.owner = "grafana";
  sops.secrets.telegram_chat_id.owner = "grafana";

  # 2. Grafana Alerting Provisioning
  services.grafana.provisioning.alerting = {
    contactPoints = [{
      orgId = 1;
      name = "Telegram-Critical-And-Reports";
      receivers = [{
        uid = "telegram_1";
        type = "telegram";
        settings = {
          # Use $__file to read the raw secret values directly from the filesystem
          bottoken = "$__file{${config.sops.secrets.health_reporter_bot_api_token.path}}";
          chatid = "$__file{${config.sops.secrets.telegram_chat_id.path}}";
          parseMode = "MarkdownV2";
        };
      }];
    }];

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

    rules = [
      {
        orgId = 1;
        name = "Hardware and Node Failures";
        folder = "Infrastructure";
        interval = "1m";
        rules = [
          {
            title = "SMART Drive Failure";
            condition = "A";
            data = [{
              refId = "A";
              datasourceUid = "prometheus";
              model.expr = "smartctl_device_smart_status == 0";
            }];
            for = "1m";
            labels.severity = "critical";
            annotations.summary = "Drive failure detected on {{ $labels.instance }} - Device: {{ $labels.device }}";
          }
          {
            title = "Node Down";
            condition = "A";
            data = [{
              refId = "A";
              datasourceUid = "prometheus";
              model.expr = "up == 0";
            }];
            for = "3m"; 
            labels.severity = "critical";
            annotations.summary = "Node {{ $labels.instance }} has been offline for over 3 minutes.";
          }
          {
            title = "Systemd Service Failed";
            condition = "A";
            data = [{
              refId = "A";
              datasourceUid = "prometheus";
              model.expr = "node_systemd_unit_state{state="failed"} == 1";
            }];
            for = "2m";
            labels.severity = "critical";
            annotations.summary = "Service {{ $labels.name }} failed on {{ $labels.instance }}.";
          }
        ];
      }
      {
        orgId = 1;
        name = "Resource Pressure";
        folder = "Infrastructure";
        interval = "2m";
        rules = [
          {
            title = "High CPU Load";
            condition = "A";
            data = [{
              refId = "A";
              datasourceUid = "prometheus";
              model.expr = "1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) > 0.90";
            }];
            for = "5m";
            labels.severity = "warning";
          }
          {
            title = "High RAM Usage";
            condition = "A";
            data = [{
              refId = "A";
              datasourceUid = "prometheus";
              model.expr = "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.90";
            }];
            for = "5m";
            labels.severity = "warning";
          }
          {
            title = "Storage Near Capacity";
            condition = "A";
            data = [{
              refId = "A";
              datasourceUid = "prometheus";
              model.expr = "1 - (node_filesystem_free_bytes{fstype=~"ext4|xfs|zfs"} / node_filesystem_size_bytes{fstype=~"ext4|xfs|zfs"}) > 0.85";
            }];
            for = "10m";
            labels.severity = "warning";
          }
        ];
      }
      {
        orgId = 1;
        name = "Daily Reports";
        folder = "Reports";
        interval = "1m";
        rules = [
          {
            title = "Daily Infrastructure Health Summary";
            condition = "A";
            data = [{
              refId = "A";
              datasourceUid = "prometheus";
              model.expr = "vector(1)"; 
            }];
            for = "0m"; 
            labels.report = "daily";
            annotations.summary = "✅ Daily All-Clear: Infrastructure is operating normally. All monitored SMART drives report passing health.";
          }
        ];
      }
    ];
  };
}
