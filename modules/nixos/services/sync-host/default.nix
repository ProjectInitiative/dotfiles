{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.sync-host;
  
  # Create the sync script with bcachefs service monitoring
  syncScriptPath = pkgs.writeText "sync-host-script.py" ''
    #!${pkgs.python3}/bin/python3

    import subprocess
    import sys
    import json
    import os
    import concurrent.futures
    import time
    from datetime import datetime

    # Configuration passed from Nix
    RCLONE_BIN = "${pkgs.rclone}/bin/rclone"
    RCLONE_CONFIG = "${cfg.rcloneConfigFile}"
    REMOTES = ${builtins.toJSON cfg.rcloneRemotes}
    LOCAL_TARGET = "${cfg.localTargetPath}"
    WAKEUP_DELAY = "${cfg.wakeUpDelay}"
    SHOULD_POWER_OFF = ${lib.boolToString cfg.powerOff}
    DISABLE_RTC_WAKE = ${lib.boolToString cfg.disableRTCWake}
    MAX_WORKERS = ${toString cfg.maxWorkers}
    BCACHEFS_MOUNTPOINT = "${cfg.bcachefsMountpoint}"

    def run_rclone_sync(remote):
        """Executes a single rclone sync command."""
        print(f"Starting sync for: {remote}")
        
        # Create target directory for this remote
        remote_name = remote.split(':')[0]  # Extract remote name from 'remote:bucket/path'
        target_dir = f"{LOCAL_TARGET}/{remote_name}"
        
        # Ensure target directory exists
        os.makedirs(target_dir, exist_ok=True)
        
        command = [
            RCLONE_BIN, 'sync',
            '--config', RCLONE_CONFIG,
            '--transfers', '4',  # Rclone setting for parallel files
            '--progress',  # Show progress
            '--log-file', f'/var/log/sync-host-{remote_name}.log',
            '--log-level', 'INFO',
            remote,  # Source (e.g., 'remote1:bucket/path')
            target_dir  # Local target directory
        ]

        try:
            # Run the rclone command
            result = subprocess.run(command, check=True, capture_output=True, text=True)
            print(f"Successfully synced {remote}. Output:\n{result.stdout}")
            return True
        except subprocess.CalledProcessError as e:
            print(f"Error syncing {remote}: {e}")
            print(f"Stderr: {e.stderr}")
            return False

    def run_additional_backup_tasks():
        """Run additional backup tasks defined in configuration."""
        print("Running additional backup tasks...")
        # Example: rsync, custom scripts, etc.
        return True

    def take_bcachefs_snapshot():
        """Trigger bcachefs snapshot service if bcachefs is mounted."""
        try:
            # Check if bcachefs-tools is available and pool exists
            result = subprocess.run([
                "${pkgs.bcachefs-tools}/bin/bcachefs", 'show-super', 
                BCACHEFS_MOUNTPOINT
            ], capture_output=True, text=True, check=False)
            
            if result.returncode == 0:
                print("Triggering bcachefs snapshot service...")
                # Use the systemd service for snapshot creation instead of direct command
                snap_result = subprocess.run([
                    "${pkgs.systemd}/bin/systemctl", 'start', 'bcachefs-snap-create.service'
                ], capture_output=True, text=True)
                
                if snap_result.returncode == 0:
                    print("Bcachefs snapshot service triggered successfully")
                    return True
                else:
                    print(f"Failed to trigger bcachefs snapshot service: {snap_result.stderr}")
                    return False
            else:
                print("Bcachefs filesystem not found at mount point, skipping snapshot")
                return True  # Not an error, just skip
        except Exception as e:
            print(f"Unexpected error during bcachefs snapshot: {e}")
            return False

    def wait_for_bcachefs_services():
        """Wait for any running bcachefs services before shutdown."""
        bcachefs_services = [
            'bcachefs-scrub-mnt-pool.service',
            'bcachefs-snap-create.service', 
            'bcachefs-snap-prune.service'
        ]
        
        print("Checking for running bcachefs services...")
        services_to_wait = []
        
        for service in bcachefs_services:
            # Check if the service exists and is active/running
            result = subprocess.run([
                "${pkgs.systemd}/bin/systemctl", 'is-active', service
            ], capture_output=True, text=True)
            
            if result.stdout.strip() in ['active', 'reloading', 'activating', 'deactivating']:
                print(f"Service {service} is running or active, will wait for completion...")
                services_to_wait.append(service)
            else:
                print(f"Service {service} is not active")
        
        # Wait for all running services to complete
        for service in services_to_wait:
            print(f"Waiting for {service} to complete...")
            while True:
                result = subprocess.run([
                    "${pkgs.systemd}/bin/systemctl", 'is-active', service
                ], capture_output=True, text=True)
                
                if result.stdout.strip() not in ['active', 'reloading', 'activating', 'deactivating']:
                    print(f"Service {service} has completed")
                    break
                
                print(f"Service {service} still running, sleeping for 30 seconds...")
                time.sleep(30)
        
        print("All bcachefs services completed, safe to proceed with shutdown")

    def set_next_wakeup():
        """Sets the RTC alarm and shuts down the system."""
        if DISABLE_RTC_WAKE:
            print("RTC wake disabled for debugging. Skipping power off and wake scheduling.")
            return
        if not SHOULD_POWER_OFF:
            print("Power off is disabled. Exiting.")
            return

        # First wait for any running bcachefs services to complete
        wait_for_bcachefs_services()

        try:
            # Calculate the wake-up time and set the alarm, then power off
            date_command = ["${pkgs.coreutils}/bin/date", "+%s", "-d", f"now + {WAKEUP_DELAY}"]

            # Execute rtcwake command
            rtcwake_command = [
                "${pkgs.rtcwake}/bin/rtcwake",
                "-m", "off",  # Power off mode
                "-t", subprocess.check_output(date_command, text=True).strip()
            ]

            print(f"Scheduled next wake-up with: {' '.join(rtcwake_command)}")

            # Execute the rtcwake command which performs shutdown
            subprocess.run(rtcwake_command, check=True)
        except Exception as e:
            print(f"Failed to set rtcwake or power off: {e}", file=sys.stderr)
            sys.exit(1)

    def main():
        success_count = 0
        failure_count = 0
        
        # 1. Run additional backup tasks (if any)
        print("Running additional backup tasks...")
        if not run_additional_backup_tasks():
            print("Additional backup tasks failed, continuing with rclone syncs...")
            failure_count += 1
        
        # 2. Run all rclone syncs concurrently
        if REMOTES:
            print("Starting rclone sync operations...")
            with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                # Submit all remotes to the thread pool
                future_to_remote = {executor.submit(run_rclone_sync, remote): remote for remote in REMOTES}

                # 2. Wait for all futures to complete
                for future in concurrent.futures.as_completed(future_to_remote):
                    remote = future_to_remote[future]
                    try:
                        if future.result():
                            success_count += 1
                        else:
                            failure_count += 1
                    except Exception as exc:
                        print(f'{remote} generated an exception: {exc}')
                        failure_count += 1
            
            print(f"Rclone sync complete. Successful: {success_count}, Failed: {failure_count}")
        else:
            print("No rclone remotes configured, skipping rclone syncs")
        
        # 3. Trigger bcachefs snapshot
        print("Triggering bcachefs snapshot...")
        if not take_bcachefs_snapshot():
            print("Bcachefs snapshot failed")
            failure_count += 1
        else:
            success_count += 1

        print(f"Overall sync complete. Successful: {success_count}, Failed: {failure_count}")

        # 4. Handle wake-up and power off (with bcachefs service checks)
        if failure_count == 0:
            set_next_wakeup()
        else:
            print("Not powering off due to sync failures.")
            sys.exit(1)

    if __name__ == "__main__":
        main()
  '';
in
{
  options.services.sync-host = {
    enable = mkEnableOption "Enable sync-host service";

    rcloneRemotes = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of rclone remotes to sync.";
    };

    rcloneConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Rclone configuration.";
    };

    preSyncScripts = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of scripts to run before the sync.";
    };

    postSyncScripts = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of scripts to run after the sync.";
    };

    powerOff = mkOption {
      type = types.bool;
      default = true;
      description = "Power off the machine after the sync is complete.";
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

    bcachefsMountpoint = mkOption {
      type = types.str;
      default = "/mnt/storage";
      description = "Mount point for bcachefs filesystem where snapshots will be taken";
    };

    backupTasks = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "List of additional backup tasks to run";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      rclone
      python3
      rtcwake
      coreutils
      systemd
    ];

    rcloneConfigFile = pkgs.writeText "rclone.conf" cfg.rcloneConfig;

    systemd.services."sync-host" = {
      description = "Sync rclone remotes and schedule next wake";
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];

      script = ''
        ${pkgs.python3}/bin/python3 ${syncScriptPath}
      '';

      serviceConfig = {
        Type = "oneshot";
        User = "root";  # Run as root to access system functions and write to protected locations
        Restart = "no";
        TimeoutSec = "4h";  # Allow up to 4 hours for sync operations
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Timer to trigger the sync service periodically (when not using RTC wake)
    systemd.timers."sync-host" = mkIf (!cfg.powerOff) {  # Only create timer if not powering off
      description = "Timer for sync-host service";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.wakeUpTime;  # Use the configured wake time
        Persistent = true;
      };
    };
  };
}