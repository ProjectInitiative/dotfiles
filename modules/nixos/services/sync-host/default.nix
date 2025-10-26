{ config, lib, pkgs, namespace, ... }:

with lib;

let
  cfg = config.services.sync-host;

  # Use the framework to get the sync-host package from the packages directory
  syncHostPkg = pkgs.${namespace}.sync-host;
in
{
  options.services.sync-host = {
    enable = mkEnableOption "Enable sync-host service";

    rcloneRemotes = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of rclone remotes to sync.";
    };

    rcloneConfigPath = mkOption {
      type = types.path;
      default = "";
      description = "Path to rclone configuration file. Use this for SOPS secrets instead of embedding in nix store.";
    };
   
    disableRTCWake = mkOption {
      type = types.bool;
      default = false;
      description = "Disable RTC wake functionality for manual debugging.";
    };

    wakeUpTime = mkOption {
      type = types.str;
      default = "*-*-* 02:00:00";
      description = "Time to wake up the machine in the format supported by systemd.time(7).";
    };
    
    wakeUpDelay = mkOption {
      type = types.str;
      default = "24h"; # Default to 24 hours
      description = "Delay before next wake-up (e.g., '24h', '7d')";
    };

    coolOffTime = mkOption {
      type = types.str;
      default = "0s"; # No cool off time by default
      description = "Delay before shutdown to allow filesystem operations to complete (e.g., '1h', '30m')";
    };

    localTargetPath = mkOption {
      type = types.str;
      default = "/mnt/storage/backups";
      description = "Local target path for sync operations";
    };

    maxWorkers = mkOption {
      type = types.int;
      default = 4;
      description = "Maximum number of concurrent sync operations";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable debug logging for the sync-host script.";
    };

    dryRun = mkOption {
      type = types.bool;
      default = false;
      description = "Enable dry run mode for rclone sync operations.";
    };

    backupTasks = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "List of additional backup tasks to run";
    };
  };

  config = mkIf cfg.enable {

    
    systemd.services."sync-host" = {
      description = "Sync rclone remotes and schedule next wake";
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];

      script = ''
        ${syncHostPkg}/bin/sync-host \
            --rclone-config "${cfg.rcloneConfigPath}" \
            --local-target-path "${cfg.localTargetPath}" \
            --wake-up-delay "${cfg.wakeUpDelay}" \
            --cool-off-time "${cfg.coolOffTime}" \
            --max-workers ${toString cfg.maxWorkers} \
            ${optionalString cfg.disableRTCWake "--disable-rtc-wake"} \
            ${optionalString cfg.debug "--debug"} \
            ${optionalString cfg.dryRun "--dry-run"} \
            ${optionalString (cfg.rcloneRemotes != []) "--remotes ${concatMapStrings (r: "'${r}' ") cfg.rcloneRemotes}"}
      '';

        serviceConfig = {
            Type = "simple";           # 👈 Run in background (doesn't block boot)
            User = "root";
            Restart = "on-failure";    # 🔁 Retry if the script fails
            RestartSec = "60s";        # Wait 60 seconds before retry
            StartLimitIntervalSec = 600; # 10-minute failure window
            StartLimitBurst = 3;       # Max 3 retries in that window
            StandardOutput = "journal";
            StandardError = "journal";
        };

      # Run once automatically after boot (non-blocking)
      wantedBy = [ "multi-user.target" ];
    };

    # Timer to trigger the sync service periodically (when not using RTC wake)
    systemd.timers."sync-host" = mkIf (cfg.disableRTCWake) {  # Only create timer if not powering off
      description = "Timer for sync-host service";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.wakeUpTime;  # Use the configured wake time
        Persistent = true;
      };
    };
  };
}