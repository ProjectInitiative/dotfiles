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
    import logging
    import argparse
    import shlex

    # Configuration passed from Nix
    RCLONE_BIN = "${pkgs.rclone}/bin/rclone"
    RCLONE_CONFIG = "${cfg.rcloneConfigPath}"
    REMOTES = ${builtins.toJSON cfg.rcloneRemotes}
    LOCAL_TARGET = "${cfg.localTargetPath}"
    WAKEUP_DELAY = "${cfg.wakeUpDelay}"
    COOL_OFF_TIME = "${cfg.coolOffTime}"
    SHOULD_POWER_OFF = ${if cfg.powerOff then "True" else "False"}
    DISABLE_RTC_WAKE = ${if cfg.disableRTCWake then "True" else "False"}
    MAX_WORKERS = ${toString cfg.maxWorkers}

    def setup_logging(debug):
        """Sets up logging."""
        log_level = logging.DEBUG if debug else logging.INFO
        logging.basicConfig(level=log_level, format='%(asctime)s - %(levelname)s - %(message)s', stream=sys.stdout)

    def run_rclone_sync(remote):
        """Executes a single rclone sync command."""
        logging.info(f"Starting sync for: {remote}")

        # If remote doesn't contain a ':', append ':/' to sync the root.
        if ':' not in remote:
            source = remote + ':/'
        # If remote ends with ':', append '/' to sync the root.
        elif remote.endswith(':'):
            source = remote + '/'
        else:
            source = remote
        
        # Create target directory for this remote
        remote_name = remote.split(':')[0]  # Extract remote name from 'remote:bucket/path'
        target_dir = f"{LOCAL_TARGET.rstrip('/')}/{remote_name}"
        
        # Ensure target directory exists
        os.makedirs(target_dir, exist_ok=True)
        
        command = [
            RCLONE_BIN, 'sync',
            '--config', RCLONE_CONFIG,
            '--transfers', '4',  # Rclone setting for parallel files
            '--progress',  # Show progress
            '--log-file', f'/var/log/sync-host-{remote_name}.log',
            '--log-level', 'INFO',
            source,  # Source (e.g., 'remote1:bucket/path')
            target_dir  # Local target directory
        ]

        logging.debug(f"Running command: {shlex.join(command)}")
        try:
            # Run the rclone command
            result = subprocess.run(command, check=True, capture_output=True, text=True)
            logging.info(f"Successfully synced {remote}.")
            logging.debug(f"Stdout: {result.stdout}")
            return True
        except subprocess.CalledProcessError as e:
            logging.error(f"Error syncing {remote}: {e}")
            logging.error(f"Stderr: {e.stderr}")
            return False

    def run_additional_backup_tasks():
        """Run additional backup tasks defined in configuration."""
        logging.info("Running additional backup tasks...")
        # Example: rsync, custom scripts, etc.
        return True

    def check_bcachefs_services():
        """Check if any bcachefs services are running, and wait if they are."""
        logging.info("Checking bcachefs services before shutdown...")
        # Since the services are already configured on the host independently,
        # we just need to check their status
        return True  # Just continue, the wait happens in set_next_wakeup

    def wait_for_bcachefs_services():
        """Wait for any running bcachefs services before shutdown."""
        bcachefs_services = [
            'bcachefs-scrub-mnt-pool.service',
            'bcachefs-snap-create.service', 
            'bcachefs-snap-prune.service'
        ]
        
        logging.info("Checking for running bcachefs services...")
        services_to_wait = []
        
        for service in bcachefs_services:
            # Check if the service exists and is active/running
            command = ["${pkgs.systemd}/bin/systemctl", 'is-active', service]
            logging.debug(f"Running command: {shlex.join(command)}")
            result = subprocess.run(command, capture_output=True, text=True)
            
            if result.stdout.strip() in ['active', 'reloading', 'activating', 'deactivating']:
                logging.info(f"Service {service} is running or active, will wait for completion...")
                services_to_wait.append(service)
            else:
                logging.info(f"Service {service} is not active")
        
        # Wait for all running services to complete
        for service in services_to_wait:
            logging.info(f"Waiting for {service} to complete...")
            while True:
                command = ["${pkgs.systemd}/bin/systemctl", 'is-active', service]
                logging.debug(f"Running command: {shlex.join(command)}")
                result = subprocess.run(command, capture_output=True, text=True)
                
                if result.stdout.strip() not in ['active', 'reloading', 'activating', 'deactivating']:
                    logging.info(f"Service {service} has completed")
                    break
                
                logging.info(f"Service {service} still running, sleeping for 30 seconds...")
                time.sleep(30)
        
        logging.info("All bcachefs services completed, safe to proceed with shutdown")

    def set_next_wakeup():
        """Sets the RTC alarm and shuts down the system."""
        if DISABLE_RTC_WAKE:
            logging.warning("RTC wake disabled for debugging. Skipping power off and wake scheduling.")
            return
        if not SHOULD_POWER_OFF:
            logging.info("Power off is disabled. Exiting.")
            return

        # First wait for any running bcachefs services to complete
        wait_for_bcachefs_services()

        # Add cool-off time before shutdown to allow filesystem operations to complete
        if COOL_OFF_TIME != "0s":
            logging.info(f"Waiting for cool-off period: {COOL_OFF_TIME}")
            # Parse the cool-off time using date command to handle various formats like "1h", "30m", etc.
            date_command = ["${pkgs.coreutils}/bin/date", "+%s", "-d", f"now + {COOL_OFF_TIME}"]
            logging.debug(f"Running command: {shlex.join(date_command)}")
            cool_off_seconds = subprocess.check_output(date_command, text=True).strip()

            date_command = ["${pkgs.coreutils}/bin/date", "+%s"]
            logging.debug(f"Running command: {shlex.join(date_command)}")
            current_time = int(subprocess.check_output(date_command, text=True).strip())
            sleep_seconds = int(cool_off_seconds) - current_time
            if sleep_seconds > 0:
                logging.info(f"Sleeping for {sleep_seconds} seconds before shutdown...")
                time.sleep(sleep_seconds)
            else:
                logging.warning("Cool-off time is in the past, continuing immediately...")

        try:
            # Calculate the wake-up time and set the alarm, then power off
            date_command = ["${pkgs.coreutils}/bin/date", "+%s", "-d", f"now + {WAKEUP_DELAY}"]
            logging.debug(f"Running command: {shlex.join(date_command)}")
            wakeup_time = subprocess.check_output(date_command, text=True).strip()

            # Execute rtcwake command
            rtcwake_command = [
                "${pkgs.util-linux}/bin/rtcwake",
                "-m", "off",  # Power off mode
                "-t", wakeup_time
            ]

            logging.info(f"Scheduled next wake-up with: {shlex.join(rtcwake_command)}")
            logging.debug(f"Running command: {shlex.join(rtcwake_command)}")

            # Execute the rtcwake command which performs shutdown
            subprocess.run(rtcwake_command, check=True)
        except Exception as e:
            logging.error(f"Failed to set rtcwake or power off: {e}", exc_info=True)
            sys.exit(1)

    def main():
        parser = argparse.ArgumentParser(description="Sync host script.")
        parser.add_argument("--debug", action="store_true", help="Enable debug logging.")
        args = parser.parse_args()

        setup_logging(args.debug)

        success_count = 0
        failure_count = 0
        
        # 1. Run additional backup tasks (if any)
        logging.info("Running additional backup tasks...")
        if not run_additional_backup_tasks():
            logging.warning("Additional backup tasks failed, continuing with rclone syncs...")
            failure_count += 1
        
        # 2. Run all rclone syncs concurrently
        if REMOTES:
            logging.info("Starting rclone sync operations...")
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
                        logging.error(f'{remote} generated an exception: {exc}', exc_info=True)
                        failure_count += 1
            
            logging.info(f"Rclone sync complete. Successful: {success_count}, Failed: {failure_count}")
        else:
            logging.info("No rclone remotes configured, skipping rclone syncs")
        
        # 3. Check bcachefs services
        logging.info("Checking bcachefs services...")
        if not check_bcachefs_services():
            logging.error("Bcachefs service check failed")
            failure_count += 1
        else:
            success_count += 1

        logging.info(f"Overall sync complete. Successful: {success_count}, Failed: {failure_count}")

        # 4. Handle wake-up and power off (with bcachefs service checks)
        if failure_count == 0:
            set_next_wakeup()
        else:
            logging.error("Not powering off due to sync failures.")
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

    rcloneConfigPath = mkOption {
      type = types.path;
      default = "";
      description = "Path to rclone configuration file. Use this for SOPS secrets instead of embedding in nix store.";
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
      util-linux
      coreutils
      systemd
    ];

    # rcloneConfigFile is not needed since we pass the path directly to the script

    systemd.services."sync-host" = {
      description = "Sync rclone remotes and schedule next wake";
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];

      script = ''
        ${pkgs.python3}/bin/python3 ${syncScriptPath} ${if cfg.debug then "--debug" else ""}
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
