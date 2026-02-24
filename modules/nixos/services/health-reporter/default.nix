{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;

let
  cfg = config.${namespace}.services.health-reporter;
in
{
  options.${namespace}.services.health-reporter = {
    enable = mkEnableOption "Server health monitoring service";

    telegramTokenPath = mkOption {
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

    checkReadOnlyMounts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of mount points to check if they are read-only";
    };

    runAtBoot = mkOption {
      type = types.bool;
      default = false;
      description = "Run the health monitor at boot time instead of a scheduled time";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.server-health-monitor = {
      description = "Server Health Monitor";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = ''
          ${pkgs.${namespace}.health-report}/bin/health-report \
                  --send-to-telegram \
                  --telegram-token-path ${config.sops.secrets.health_reporter_bot_api_token.path} \
                  --telegram-chat-id-path ${config.sops.secrets.telegram_chat_id.path} ${
                    lib.optionalString (cfg.checkReadOnlyMounts != []) ''\
                  --check-read-only-mounts ${lib.concatStringsSep "," cfg.checkReadOnlyMounts}''
                  }
        '';
      };
    };

    # Schedule execution
    systemd.timers.server-health-monitor = {
      description = "Timer for Server Health Monitor";
      wantedBy = [ "timers.target" ];
      timerConfig = if cfg.runAtBoot then {
        OnBootSec = "5min";
        Unit = "server-health-monitor.service";
      } else {
        OnCalendar = "*-*-* ${cfg.reportTime}:00";
        Unit = "server-health-monitor.service";
        Persistent = true;
      };
    };

  };
}
