{
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  ...
}:

with lib;

let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.services.health-reporter;
in
{
  options.${namespace}.services.health-reporter = {
    enable = mkEnableOption "Server health monitoring service"; # Standard mkEnableOption

    telegramTokenPath = mkOption { # Standard mkOption
      type = types.str;
      default = "/run/secrets/telegram-token";
      description = "Path to the file containing the Telegram bot token";
    };

    telegramChatIdPath = mkOption {
      type = types.str;
      default = "/run/secrets/telegram-chatid";
      description = "Path to the file containing the Telegram chat ID";
    };

    reportTime = mkOption {
      type = types.str;
      default = "06:00";
      description = "Time to send daily report in 24h format (HH:MM)";
    };

    enableCpuMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable CPU usage and temperature monitoring";
    };

    enableMemoryMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable memory usage monitoring";
    };

    enableNetworkMonitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Enable network traffic monitoring";
    };

    excludeDrives = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "loop"
        "ram"
        "sr"
      ];
      description = "Patterns to exclude when auto-detecting drives";
    };

    excludeMountPoints = mkOption {
      type = types.listOf types.str;
      default = [
        "/run"
        "/var/lib/docker"
        "/var/lib/containers"
        "k3s"
        "kube"
        "containerd"
        "docker"
        "sandbox"
      ];
      description = "Mount point patterns to exclude from disk usage report";
    };

    criticalDiskUsage = mkOption {
      type = types.int;
      default = 90;
      description = "Disk usage percentage considered critical";
    };

    warningDiskUsage = mkOption {
      type = types.int;
      default = 75;
      description = "Disk usage percentage considered a warning";
    };

    detailedReport = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to include detailed information in the report";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.server-health-monitor = {
      description = "Server Health Monitor";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = ''
          ${pkgs.${namespace}.health-report}/bin/health-report \
                  --send-to-telegram \
                  --telegram-token-path ${config.sops.secrets.health_reporter_bot_api_token.path} \
                  --telegram-chat-id-path ${config.sops.secrets.telegram_chat_id.path}
        '';
      };
    };

    # Schedule daily execution
    systemd.timers.server-health-monitor = {
      description = "Timer for Server Health Monitor";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* ${cfg.reportTime}:00";
        Unit = "server-health-monitor.service";
        Persistent = true;
      };
    };

  };
}
