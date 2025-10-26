#!/usr/bin/env python3
import subprocess
import sys
import json
import os
import concurrent.futures
import time
from datetime import datetime, timedelta
import re
import logging
import argparse
import shlex
from pytimeparse2 import parse as parse_duration


def setup_logging(debug):
    """Sets up logging."""
    log_level = logging.DEBUG if debug else logging.INFO
    logging.basicConfig(level=log_level, format='%(asctime)s - %(levelname)s - %(message)s', stream=sys.stdout)


def run_rclone_sync(remote, rclone_config, local_target_path, dry_run):
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
    target_dir = f"{local_target_path.rstrip('/')}/{remote_name}"
    
    # Ensure target directory exists
    os.makedirs(target_dir, exist_ok=True)
    rclone_log = f'/var/log/sync-host-{remote_name}.log'
    logging.info(f'Remote {remote_name} log location: {rclone_log}')
    command = [
        'rclone', 'sync',
        '--config', rclone_config,
        '--transfers', '4',  # Rclone setting for parallel files
        '--progress',  # Show progress
        '--log-file', rclone_log,
        '--log-level', 'INFO',
        source,  # Source (e.g., 'remote1:bucket/path')
        target_dir  # Local target directory
    ]

    if dry_run:
        logging.info(f"[DRY-RUN] Would sync {remote} to {target_dir}")
        logging.info(f"[DRY-RUN] Command would be: {shlex.join(command)}")
        return True  # Return success in dry-run mode
        
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
        command = ['systemctl', 'is-active', service]
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
            command = ['systemctl', 'is-active', service]
            logging.debug(f"Running command: {shlex.join(command)}")
            result = subprocess.run(command, capture_output=True, text=True)
            
            if result.stdout.strip() not in ['active', 'reloading', 'activating', 'deactivating']:
                logging.info(f"Service {service} has completed")
                break
            
            logging.info(f"Service {service} still running, sleeping for 30 seconds...")
            time.sleep(30)
    
    logging.info("All bcachefs services completed, safe to proceed with shutdown")


def create_bcachefs_snapshot():
    """Creates a bcachefs snapshot by starting the systemd service."""
    # TODO: Consolidate bcachefs snapshot management with the external module.
    logging.info("Creating bcachefs snapshot...")
    command = ["systemctl", "start", "bcachefs-snap-create.service"]
    logging.debug(f"Running command: {shlex.join(command)}")
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
        logging.info("Successfully started bcachefs snapshot creation. Waiting for it to complete...")
        logging.debug(f"Stdout: {result.stdout}")
        return True
    except subprocess.CalledProcessError as e:
        logging.error(f"Error starting bcachefs snapshot creation: {e}")
        logging.error(f"Stderr: {e.stderr}")
        return False


def set_next_wakeup(wake_up_delay, cool_off_time, disable_rtc_wake):
    """Sets the RTC alarm and shuts down the system."""
    if disable_rtc_wake:
        logging.warning("RTC wake disabled for debugging. Skipping power off and wake scheduling.")
        return

    # Add cool-off time before shutdown to allow filesystem operations to complete
    if cool_off_time != "0s":
        logging.info(f"Waiting for cool-off period: {cool_off_time}")
        # Parse the cool-off time and sleep for that duration
        cool_off_seconds = parse_duration(cool_off_time)
        logging.info(f"Sleeping for {cool_off_seconds} seconds before shutdown...")
        time.sleep(cool_off_seconds)

    # finally wait for any running bcachefs services to complete
    wait_for_bcachefs_services()

    try:
        # Calculate the wake-up time and set the alarm, then power off
        # Calculate the future time based on the delay from now
        wakeup_delay_seconds = parse_duration(wake_up_delay)
        future_time = datetime.now() + timedelta(seconds=wakeup_delay_seconds)
        wakeup_timestamp = int(future_time.timestamp())

        # Execute rtcwake command
        rtcwake_command = [
            'rtcwake',
            "-m", "off",  # Power off mode
            "-t", str(wakeup_timestamp)
        ]

        logging.info(f"Scheduled next wake-up with: {shlex.join(rtcwake_command)}")
        logging.debug(f"Running command: {shlex.join(rtcwake_command)}")

        # Execute the rtcwake command which performs shutdown
        subprocess.run(rtcwake_command, check=True)
    except Exception as e:
        logging.error(f"Failed to set rtcwake or power off: {e}", exc_info=True)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Sync host script with CLI arguments.")
    parser.add_argument("--rclone-config", required=True, 
                       help="Path to rclone configuration file")
    parser.add_argument("--remotes", nargs="+", default=[],
                       help="List of rclone remotes to sync")
    parser.add_argument("--local-target-path", default="/mnt/storage/backups",
                       help="Local target path for sync operations")
    parser.add_argument("--wake-up-delay", default="24h",
                       help="Delay before next wake-up (e.g., '24h', '7d')")
    parser.add_argument("--cool-off-time", default="0s",
                       help="Delay before shutdown to allow filesystem operations to complete (e.g., '1h', '30m')")
    parser.add_argument("--disable-rtc-wake", action="store_true",
                       help="Disable RTC wake functionality for manual debugging")
    parser.add_argument("--max-workers", type=int, default=4,
                       help="Maximum number of concurrent sync operations")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging.")
    parser.add_argument("--dry-run", action="store_true", help="Enable dry-run mode, skipping actual sync operations.")
    
    args = parser.parse_args()

    setup_logging(args.debug)
    
    success_count = 0
    failure_count = 0
    
    # 1. Manually trigger a snapshot before syncing.
    if not create_bcachefs_snapshot():
        logging.error("Failed to create bcachefs snapshot. Aborting sync.")
        sys.exit(1)

    # 2. Run additional backup tasks (if any)
    logging.info("Running additional backup tasks...")
    if not run_additional_backup_tasks():
        logging.warning("Additional backup tasks failed, continuing with rclone syncs...")
        failure_count += 1
    
    # 3. Run all rclone syncs concurrently
    if args.remotes:
        logging.info("Starting rclone sync operations...")
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.max_workers) as executor:
            # Submit all remotes to the thread pool
            future_to_remote = {executor.submit(run_rclone_sync, remote, args.rclone_config, args.local_target_path, args.dry_run): remote for remote in args.remotes}

            # 3. Wait for all futures to complete
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
    
    # 4. Check bcachefs services
    logging.info("Checking bcachefs services...")
    if not check_bcachefs_services():
        logging.error("Bcachefs service check failed")
        failure_count += 1
    else:
        success_count += 1

    logging.info(f"Overall sync complete. Successful: {success_count}, Failed: {failure_count}")

    # 5. Handle wake-up and power off (with bcachefs service checks)
    if failure_count == 0:
        set_next_wakeup(args.wake_up_delay, args.cool_off_time, args.disable_rtc_wake)
    else:
        logging.error("Not powering off due to sync failures.")
        sys.exit(1)


if __name__ == "__main__":
    main()
