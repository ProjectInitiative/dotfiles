#!/usr/bin/env python3
# bcachefs_snap.py

import os
import subprocess
import argparse
import configparser
from datetime import datetime, timedelta
from collections import defaultdict
import sys

# --- Configuration ---
DEFAULT_SNAPSHOTS_SUBDIR_NAME = ".bcachefs_snapshots" # Default name for the directory holding snapshots
DATETIME_FORMAT = "%Y-%m-%d_%H-%M-%S"                 # Format for snapshot names and parsing

# --- Helper Functions ---
def run_command(command_args, check=True):
    """
    Executes a shell command using subprocess.
    Args:
        command_args (list): The command and its arguments as a list of strings.
        check (bool): If True, raises CalledProcessError if the command returns a non-zero exit code.
    Returns:
        tuple: (stdout, stderr) strings if successful.
    Raises:
        subprocess.CalledProcessError: If the command fails and check is True.
        FileNotFoundError: If the command executable is not found.
    """
    try:
        # For debugging: print(f"Executing: {' '.join(command_args)}")
        result = subprocess.run(command_args, capture_output=True, text=True, check=check)
        return result.stdout.strip(), result.stderr.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {' '.join(e.cmd)}", file=sys.stderr)
        print(f"Return code: {e.returncode}", file=sys.stderr)
        print(f"Stdout: {e.stdout.strip()}", file=sys.stderr)
        print(f"Stderr: {e.stderr.strip()}", file=sys.stderr)
        raise # Re-raise the exception if check=True
    except FileNotFoundError:
        print(f"Error: The command '{command_args[0]}' was not found. "
              "Is bcachefs-tools installed and in your PATH?", file=sys.stderr)
        sys.exit(1)

def get_current_datetime_str():
    """Returns the current datetime formatted as a string for snapshot names."""
    return datetime.now().strftime(DATETIME_FORMAT)

def parse_snapshot_name(name):
    """
    Parses a snapshot name string (expected to be in DATETIME_FORMAT) into a datetime object.
    Args:
        name (str): The snapshot name.
    Returns:
        datetime: A datetime object if parsing is successful, None otherwise.
    """
    try:
        return datetime.strptime(name, DATETIME_FORMAT)
    except ValueError:
        return None

# --- Core bcachefs Operations ---
def _get_snapshots_dir_path(parent_subvolume, snapshots_subdir_name):
    """Constructs the full path to the snapshots directory."""
    return os.path.join(parent_subvolume, snapshots_subdir_name)

def _get_full_snapshot_path(parent_subvolume, snapshots_subdir_name, snapshot_name):
    """Constructs the full path to a specific snapshot file/directory."""
    return os.path.join(parent_subvolume, snapshots_subdir_name, snapshot_name)

def ensure_snapshots_subdir_exists(parent_subvolume, snapshots_subdir_name, dry_run=False):
    """
    Ensures the snapshots subdirectory exists within the parent subvolume.
    If it doesn't exist, it attempts to create it as a bcachefs subvolume.
    Args:
        parent_subvolume (str): Absolute path to the parent bcachefs subvolume.
        snapshots_subdir_name (str): Name of the subdirectory to store snapshots.
        dry_run (bool): If True, only print what would be done.
    Returns:
        str: The absolute path to the snapshots directory.
    Exits:
        If creation fails.
    """
    snapshots_dir = _get_snapshots_dir_path(parent_subvolume, snapshots_subdir_name)
    if not os.path.isdir(snapshots_dir):
        print(f"Snapshots directory '{snapshots_dir}' not found.")
        if dry_run:
            print(f"Dry run: Would attempt to create bcachefs subvolume: {snapshots_dir}")
            return snapshots_dir # Assume success for dry run for further steps

        print(f"Attempting to create bcachefs subvolume: {snapshots_dir}")
        try:
            # Command: bcachefs subvolume create <path_to_snapshots_dir>
            run_command(["bcachefs", "subvolume", "create", snapshots_dir])
            print(f"Successfully created snapshots subvolume: {snapshots_dir}")
        except Exception as e:
            print(f"Failed to create snapshots subvolume '{snapshots_dir}'. Error: {e}", file=sys.stderr)
            print("Please ensure the parent subvolume exists, is on a bcachefs filesystem, "
                  "and you have necessary permissions.", file=sys.stderr)
            sys.exit(1)
    return snapshots_dir

def create_snapshot(parent_subvolume, snapshots_subdir_name, read_only=True, dry_run=False):
    """
    Creates a new snapshot of the parent subvolume.
    Args:
        parent_subvolume (str): Absolute path to the parent bcachefs subvolume.
        snapshots_subdir_name (str): Name of the subdirectory for snapshots.
        read_only (bool): If True, create a read-only snapshot.
        dry_run (bool): If True, only print what would be done.
    Returns:
        str: Path to the created snapshot, or simulated path if dry_run.
    Exits:
        If snapshot creation fails (and not dry_run).
    """
    # Ensure the main directory for all snapshots exists or is created
    ensure_snapshots_subdir_exists(parent_subvolume, snapshots_subdir_name, dry_run)

    snapshot_name = get_current_datetime_str()
    snapshot_dest_path = _get_full_snapshot_path(parent_subvolume, snapshots_subdir_name, snapshot_name)

    print(f"Attempting to create snapshot of '{parent_subvolume}' at '{snapshot_dest_path}'...")
    if dry_run:
        print(f"Dry run: Would create snapshot. Source: '{parent_subvolume}', Destination: '{snapshot_dest_path}', Read-only: {read_only}")
        return snapshot_dest_path

    cmd = ["bcachefs", "subvolume", "snapshot"]
    if read_only:
        cmd.append("-r") # bcachefs snapshot option for read-only
    cmd.extend([parent_subvolume, snapshot_dest_path])

    try:
        stdout, stderr = run_command(cmd)
        print(f"Successfully created snapshot: {snapshot_dest_path}")
        if stdout: print(f"  Stdout: {stdout}")
        if stderr: print(f"  Stderr: {stderr}", file=sys.stderr) # Some info might go to stderr
        return snapshot_dest_path
    except Exception as e:
        print(f"Failed to create snapshot. Error: {e}", file=sys.stderr)
        sys.exit(1)

def list_snapshots(parent_subvolume, snapshots_subdir_name):
    """
    Lists all valid snapshots in the snapshots directory.
    A valid snapshot is a directory whose name matches the DATETIME_FORMAT.
    Args:
        parent_subvolume (str): Absolute path to the parent bcachefs subvolume.
        snapshots_subdir_name (str): Name of the subdirectory containing snapshots.
    Returns:
        list: A list of (name, datetime_obj) tuples, sorted by datetime (newest first).
    """
    snapshots_dir = _get_snapshots_dir_path(parent_subvolume, snapshots_subdir_name)
    if not os.path.isdir(snapshots_dir):
        # This is not an error, just means no snapshots (or dir) yet.
        return []

    snapshots = []
    try:
        for name in os.listdir(snapshots_dir):
            full_path = os.path.join(snapshots_dir, name)
            # Crucially, bcachefs subvolumes (including snapshots) are directories.
            if os.path.isdir(full_path):
                dt_obj = parse_snapshot_name(name)
                if dt_obj: # If name matches our format, it's considered a managed snapshot
                    snapshots.append((name, dt_obj))
    except OSError as e:
        print(f"Error listing snapshots in '{snapshots_dir}': {e}", file=sys.stderr)
        return [] # Return empty list on error to prevent further issues

    # Sort by datetime object (index 1), newest first
    snapshots.sort(key=lambda x: x[1], reverse=True)
    return snapshots

def delete_snapshot(parent_subvolume, snapshots_subdir_name, snapshot_name, dry_run=False):
    """
    Deletes a specific snapshot.
    Args:
        parent_subvolume (str): Absolute path to the parent bcachefs subvolume.
        snapshots_subdir_name (str): Name of the subdirectory containing the snapshot.
        snapshot_name (str): The name of the snapshot to delete.
        dry_run (bool): If True, only print what would be done.
    """
    snapshot_path = _get_full_snapshot_path(parent_subvolume, snapshots_subdir_name, snapshot_name)
    print(f"Attempting to delete snapshot: {snapshot_path}...")

    if dry_run:
        print(f"Dry run: Would delete snapshot: {snapshot_path}")
        return

    cmd = ["bcachefs", "subvolume", "delete", snapshot_path]
    try:
        stdout, stderr = run_command(cmd)
        print(f"Successfully deleted snapshot: {snapshot_path}")
        if stdout: print(f"  Stdout: {stdout}")
        if stderr: print(f"  Stderr: {stderr}", file=sys.stderr)
    except Exception as e:
        # Log error but don't necessarily exit, as pruning might continue with other deletions
        # or this might be one of several errors.
        print(f"Failed to delete snapshot '{snapshot_path}'. Error: {e}", file=sys.stderr)

# --- Retention Policy Logic ---
def prune_snapshots(parent_subvolume, snapshots_subdir_name, retention_policy, dry_run=False):
    """
    Prunes snapshots based on the retention policy.
    Args:
        parent_subvolume (str): Absolute path to the parent bcachefs subvolume.
        snapshots_subdir_name (str): Name of the subdirectory containing snapshots.
        retention_policy (dict): {'hourly': H, 'daily': D, 'weekly': W, 'monthly': M, 'yearly': Y}
                                 Specifies how many snapshots of each period type to keep.
        dry_run (bool): If True, simulate deletion and print actions.
    """
    all_snaps_with_dt = list_snapshots(parent_subvolume, snapshots_subdir_name)
    if not all_snaps_with_dt:
        print("No snapshots found to prune.")
        return

    # Snapshots are already sorted newest first by list_snapshots
    keep_snapshots_names = set() # A set of snapshot names (strings) to keep

    # Helper function to select snapshots to keep for a given period
    def apply_period_retention(snapshots, count, period_extractor_func):
        if count <= 0:
            return

        # Group snapshots by the extracted period (e.g., (year, month, day) for daily)
        # defaultdict(list) creates a list for a new key automatically
        grouped_by_period = defaultdict(list)
        for name, dt_obj in snapshots:
            period_key = period_extractor_func(dt_obj)
            grouped_by_period[period_key].append((name, dt_obj))

        # For each period group, keep the newest snapshot
        # Then, from these candidates, keep the N most recent periods
        # Sort period keys from newest to oldest
        sorted_period_keys = sorted(grouped_by_period.keys(), reverse=True)

        kept_periods = 0
        for period_key in sorted_period_keys:
            if kept_periods >= count:
                break
            # Snapshots within each group are not necessarily sorted,
            # but we want the newest one from that period.
            # Since all_snaps_with_dt was sorted newest first, the first one
            # encountered for a period *should* be the newest.
            # To be absolutely sure, sort snapshots within this period group.
            period_snapshots = sorted(grouped_by_period[period_key], key=lambda x: x[1], reverse=True)
            if period_snapshots:
                keep_snapshots_names.add(period_snapshots[0][0]) # Add name of the newest snapshot in this period
                kept_periods += 1

    # Apply retention policies: hourly, daily, weekly, monthly, yearly
    # The order of application here doesn't strictly matter due to using a set for keep_snapshots_names
    if retention_policy.get('hourly', 0) > 0:
        apply_period_retention(all_snaps_with_dt, retention_policy['hourly'],
                               lambda dt: (dt.year, dt.month, dt.day, dt.hour))
    if retention_policy.get('daily', 0) > 0:
        apply_period_retention(all_snaps_with_dt, retention_policy['daily'],
                               lambda dt: (dt.year, dt.month, dt.day))
    if retention_policy.get('weekly', 0) > 0:
        apply_period_retention(all_snaps_with_dt, retention_policy['weekly'],
                               lambda dt: (dt.isocalendar().year, dt.isocalendar().week))
    if retention_policy.get('monthly', 0) > 0:
        apply_period_retention(all_snaps_with_dt, retention_policy['monthly'],
                               lambda dt: (dt.year, dt.month))
    if retention_policy.get('yearly', 0) > 0:
        apply_period_retention(all_snaps_with_dt, retention_policy['yearly'],
                               lambda dt: dt.year)

    # Determine snapshots to delete
    print(f"\nSnapshot Pruning Plan for '{_get_snapshots_dir_path(parent_subvolume, snapshots_subdir_name)}':")
    print(f"Total snapshots found: {len(all_snaps_with_dt)}")
    print(f"Snapshots to keep based on policy ({len(keep_snapshots_names)}):")
    # Sort names for display by parsing them back to datetime
    for name in sorted(list(keep_snapshots_names), key=lambda n: parse_snapshot_name(n) or datetime.min, reverse=True):
        print(f"  - KEEP: {name}")

    snapshots_to_delete_names = []
    for name, dt_obj in all_snaps_with_dt: # Iterate through all existing snapshots
        if name not in keep_snapshots_names:
            snapshots_to_delete_names.append(name)

    if not snapshots_to_delete_names:
        print("\nNo snapshots to delete based on the current retention policy.")
        return

    print(f"\nSnapshots to delete ({len(snapshots_to_delete_names)}):")
    # Sort names for display (e.g., oldest first for deletion list)
    for name in sorted(snapshots_to_delete_names, key=lambda n: parse_snapshot_name(n) or datetime.min):
        print(f"  - DELETE: {name}")

    if dry_run:
        print("\nDry run: No snapshots will be deleted.")
        return

    # Confirmation prompt before actual deletion
    confirm = input("\nProceed with deletion of the above listed snapshots? (yes/NO): ")
    if confirm.lower() == 'yes':
        print("Deleting snapshots...")
        for snap_name in snapshots_to_delete_names:
            delete_snapshot(parent_subvolume, snapshots_subdir_name, snap_name, dry_run=False) # dry_run is false here
        print("\nPruning complete.")
    else:
        print("\nPruning aborted by user.")

# --- Main Application Logic ---
def main():
    parser = argparse.ArgumentParser(
        description="Manages bcachefs snapshots with creation and retention policies.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter # Shows default values in help
    )
    parser.add_argument(
        "--config",
        default="/etc/bcachefs-snap.conf",
        help="Path to the configuration file."
    )
    parser.add_argument(
        "--parent-subvolume",
        help="Parent bcachefs subvolume to snapshot (overrides config file)."
    )
    parser.add_argument(
        "--snapshots-subdir",
        default=DEFAULT_SNAPSHOTS_SUBDIR_NAME,
        help="Subdirectory name within the parent subvolume for storing snapshots (overrides config)."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulate actions without making any changes to the filesystem."
    )

    subparsers = parser.add_subparsers(dest="action", required=True, help="Action to perform")

    # --- Create snapshot action ---
    create_parser = subparsers.add_parser("create", help="Create a new snapshot.")
    create_parser.add_argument(
        "--read-only",
        action=argparse.BooleanOptionalAction, # Creates --read-only and --no-read-only
        default=True,
        help="Create a read-only snapshot."
    )

    # --- Prune snapshots action ---
    prune_parser = subparsers.add_parser("prune", help="Prune old snapshots based on retention policy.")
    # Allow overriding config retention values via command line for the prune action
    prune_parser.add_argument("--hourly", type=int, help="Override number of hourly snapshots to keep.")
    prune_parser.add_argument("--daily", type=int, help="Override number of daily snapshots to keep.")
    prune_parser.add_argument("--weekly", type=int, help="Override number of weekly snapshots to keep.")
    prune_parser.add_argument("--monthly", type=int, help="Override number of monthly snapshots to keep.")
    prune_parser.add_argument("--yearly", type=int, help="Override number of yearly snapshots to keep.")

    args = parser.parse_args()

    # --- Load Configuration ---
    config = configparser.ConfigParser(allow_no_value=True) # allow_no_value for potentially empty settings
    # Set default values that can be overridden by the config file or command line
    # These are defaults for the ConfigParser object before reading the file
    config['bcachefs_snapper'] = {
        'parent_subvolume': '', # Must be provided
        'snapshots_subdir_name': args.snapshots_subdir, # Use cmd line arg as default if not in file
    }
    config['retention'] = {
        'hourly': '0', 'daily': '0', 'weekly': '0', 'monthly': '0', 'yearly': '0',
    }

    if os.path.exists(args.config):
        try:
            config.read(args.config)
            print(f"Loaded configuration from: {args.config}")
        except configparser.Error as e:
            print(f"Warning: Error reading config file '{args.config}': {e}. Using defaults/CLI args.", file=sys.stderr)
    else:
        # Only warn if a non-default config path was specified but not found
        if args.config != "/etc/bcachefs-snap.conf":
             print(f"Warning: Config file '{args.config}' not found. Using defaults/CLI args.", file=sys.stderr)

    # --- Determine effective settings (CLI > Config File > Defaults) ---
    parent_subvolume = args.parent_subvolume or config.get('bcachefs_snapper', 'parent_subvolume', fallback=None)
    # For snapshots_subdir, args.snapshots_subdir already has a default.
    # If config file has a value, it overrides args.snapshots_subdir default.
    # If args.snapshots_subdir is explicitly set on CLI, it overrides config.
    snapshots_subdir_name = config.get('bcachefs_snapper', 'snapshots_subdir_name', fallback=args.snapshots_subdir)
    if args.snapshots_subdir != DEFAULT_SNAPSHOTS_SUBDIR_NAME: # If user specified it on CLI
        snapshots_subdir_name = args.snapshots_subdir


    if not parent_subvolume:
        print("Error: Parent subvolume not specified. "
              "Use --parent-subvolume argument or set 'parent_subvolume' in the [bcachefs_snapper] section of the config file.", file=sys.stderr)
        parser.print_help()
        sys.exit(1)
    
    parent_subvolume = os.path.abspath(parent_subvolume) # Ensure it's an absolute path

    # Prepare retention policy, using CLI args if provided, else config, else default (0)
    retention_policy_values = {}
    for period in ['hourly', 'daily', 'weekly', 'monthly', 'yearly']:
        cli_value = getattr(args, period, None) if hasattr(args, period) else None
        if cli_value is not None:
            retention_policy_values[period] = cli_value
        else:
            retention_policy_values[period] = config.getint('retention', period, fallback=0)
    
    if args.dry_run:
        print("\n--- DRY RUN MODE ENABLED: No changes will be made to the filesystem. ---\n")

    # --- Perform Action ---
    if args.action == "create":
        create_snapshot(parent_subvolume, snapshots_subdir_name, args.read_only, args.dry_run)
    elif args.action == "prune":
        print(f"Pruning snapshots for '{_get_snapshots_dir_path(parent_subvolume, snapshots_subdir_name)}'")
        print("Effective retention policy:")
        for period, count in retention_policy_values.items():
            print(f"  - Keep {period.capitalize()}: {count}")
        prune_snapshots(parent_subvolume, snapshots_subdir_name, retention_policy_values, args.dry_run)
    else:
        # Should not happen due to 'required=True' for subparsers
        parser.print_help()
        sys.exit(1)

if __name__ == "__main__":
    main()

