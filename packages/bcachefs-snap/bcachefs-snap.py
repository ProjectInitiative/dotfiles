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
DEFAULT_CONFIG_PATH = "/etc/bcachefs-snap.conf"

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
        # print(f"DEBUG: Executing: {' '.join(command_args)}") # Uncomment for debugging
        result = subprocess.run(command_args, capture_output=True, text=True, check=check)
        return result.stdout.strip(), result.stderr.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {' '.join(e.cmd)}", file=sys.stderr)
        print(f"Return code: {e.returncode}", file=sys.stderr)
        print(f"Stdout: {e.stdout.strip()}", file=sys.stderr)
        print(f"Stderr: {e.stderr.strip()}", file=sys.stderr)
        raise
    except FileNotFoundError:
        print(f"Error: The command '{command_args[0]}' was not found. "
              "Is bcachefs-tools installed and in your PATH?", file=sys.stderr)
        sys.exit(1) # Critical error, cannot proceed

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

# --- Core bcachefs Operations (operate on a single target config) ---
def _get_snapshots_dir_path(parent_subvolume, snapshots_subdir_name):
    """Constructs the full path to the snapshots directory."""
    return os.path.join(parent_subvolume, snapshots_subdir_name)

def _get_full_snapshot_path(parent_subvolume, snapshots_subdir_name, snapshot_name):
    """Constructs the full path to a specific snapshot file/directory."""
    return os.path.join(parent_subvolume, snapshots_subdir_name, snapshot_name)

def ensure_snapshots_subdir_exists(target_name, parent_subvolume, snapshots_subdir_name, dry_run=False):
    """
    Ensures the snapshots subdirectory exists. Creates it as a bcachefs subvolume if not.
    Returns the path to the snapshots directory, or None on failure to create.
    """
    snapshots_dir = _get_snapshots_dir_path(parent_subvolume, snapshots_subdir_name)
    if not os.path.isdir(snapshots_dir):
        print(f"INFO [{target_name}]: Snapshots directory '{snapshots_dir}' not found.")
        if dry_run:
            print(f"DRY-RUN [{target_name}]: Would attempt to create bcachefs subvolume: {snapshots_dir}")
            return snapshots_dir # Assume success for dry run for further steps

        print(f"INFO [{target_name}]: Attempting to create bcachefs subvolume: {snapshots_dir}")
        try:
            run_command(["bcachefs", "subvolume", "create", snapshots_dir])
            print(f"SUCCESS [{target_name}]: Created snapshots subvolume: {snapshots_dir}")
        except Exception as e:
            print(f"ERROR [{target_name}]: Failed to create snapshots subvolume '{snapshots_dir}'. Error: {e}", file=sys.stderr)
            return None # Indicate failure
    return snapshots_dir

def create_snapshot_for_target(target_config, dry_run=False):
    """
    Creates a new snapshot for a specific target.
    Args:
        target_config (dict): Configuration for the target.
        dry_run (bool): If True, only print what would be done.
    Returns:
        str or None: Path to the created snapshot, or None on failure.
    """
    target_name = target_config['name']
    parent_subvolume = target_config['parent_subvolume']
    snapshots_subdir_name = target_config['snapshots_subdir_name']
    read_only = target_config.get('read_only', True) # Default to True if not specified

    print(f"\n--- Creating snapshot for Target: {target_name} ---")
    print(f"  Parent subvolume: {parent_subvolume}")
    print(f"  Snapshots subdir: {snapshots_subdir_name}")
    print(f"  Read-only: {read_only}")

    # Ensure the main directory for all snapshots for this target exists or is created
    snap_dir_path = ensure_snapshots_subdir_exists(target_name, parent_subvolume, snapshots_subdir_name, dry_run)
    if not snap_dir_path and not dry_run: # If creation failed and not a dry run
        print(f"ERROR [{target_name}]: Skipping snapshot creation due to issues with snapshots directory setup.")
        return None

    snapshot_name_ts = get_current_datetime_str()
    snapshot_dest_path = _get_full_snapshot_path(parent_subvolume, snapshots_subdir_name, snapshot_name_ts)

    if dry_run:
        print(f"DRY-RUN [{target_name}]: Would create snapshot. Source: '{parent_subvolume}', Destination: '{snapshot_dest_path}', Read-only: {read_only}")
        return snapshot_dest_path # Simulate success

    print(f"INFO [{target_name}]: Attempting to create snapshot of '{parent_subvolume}' at '{snapshot_dest_path}'...")
    cmd = ["bcachefs", "subvolume", "snapshot"]
    if read_only:
        cmd.append("-r")
    cmd.extend([parent_subvolume, snapshot_dest_path])

    try:
        stdout, stderr = run_command(cmd)
        print(f"SUCCESS [{target_name}]: Created snapshot: {snapshot_dest_path}")
        if stdout: print(f"  Stdout: {stdout}")
        if stderr: print(f"  Stderr: {stderr}", file=sys.stderr)
        return snapshot_dest_path
    except Exception as e:
        print(f"ERROR [{target_name}]: Failed to create snapshot. Error: {e}", file=sys.stderr)
        return None

def list_snapshots_for_target(target_name, parent_subvolume, snapshots_subdir_name):
    """
    Lists all valid snapshots for a specific target.
    """
    snapshots_dir = _get_snapshots_dir_path(parent_subvolume, snapshots_subdir_name)
    if not os.path.isdir(snapshots_dir):
        # This is not an error for listing, just means no snapshots (or dir) yet.
        return []

    snapshots = []
    try:
        for name in os.listdir(snapshots_dir):
            full_path = os.path.join(snapshots_dir, name)
            if os.path.isdir(full_path): # Snapshots are directories
                dt_obj = parse_snapshot_name(name)
                if dt_obj:
                    snapshots.append((name, dt_obj))
    except OSError as e:
        print(f"ERROR [{target_name}]: Error listing snapshots in '{snapshots_dir}': {e}", file=sys.stderr)
        return []
    snapshots.sort(key=lambda x: x[1], reverse=True) # Newest first
    return snapshots

def delete_snapshot_for_target(target_name, parent_subvolume, snapshots_subdir_name, snapshot_name_to_delete, dry_run=False):
    """
    Deletes a specific snapshot for a target.
    """
    snapshot_path = _get_full_snapshot_path(parent_subvolume, snapshots_subdir_name, snapshot_name_to_delete)

    if dry_run:
        print(f"DRY-RUN [{target_name}]: Would delete snapshot: {snapshot_path}")
        return True # Simulate success for dry run

    print(f"INFO [{target_name}]: Attempting to delete snapshot: {snapshot_path}...")
    cmd = ["bcachefs", "subvolume", "delete", snapshot_path]
    try:
        stdout, stderr = run_command(cmd)
        print(f"SUCCESS [{target_name}]: Deleted snapshot: {snapshot_path}")
        if stdout: print(f"  Stdout: {stdout}")
        if stderr: print(f"  Stderr: {stderr}", file=sys.stderr)
        return True
    except Exception as e:
        print(f"ERROR [{target_name}]: Failed to delete snapshot '{snapshot_path}'. Error: {e}", file=sys.stderr)
        return False

def prune_snapshots_for_target(target_config, dry_run=False, auto_confirm=False):
    """
    Prunes snapshots for a specific target based on its retention policy.
    """
    target_name = target_config['name']
    parent_subvolume = target_config['parent_subvolume']
    snapshots_subdir_name = target_config['snapshots_subdir_name']
    retention_policy = target_config['retention']

    print(f"\n--- Pruning snapshots for Target: {target_name} ---")
    print(f"  Parent subvolume: {parent_subvolume}")
    print(f"  Snapshots subdir: {snapshots_subdir_name}")
    print(f"  Retention policy: {retention_policy}")

    all_snaps_with_dt = list_snapshots_for_target(target_name, parent_subvolume, snapshots_subdir_name)
    if not all_snaps_with_dt:
        print(f"INFO [{target_name}]: No snapshots found to prune.")
        return

    keep_snapshots_names = set()

    def apply_period_retention(snapshots, count, period_extractor_func):
        if count <= 0: return
        grouped_by_period = defaultdict(list)
        for name, dt_obj in snapshots:
            grouped_by_period[period_extractor_func(dt_obj)].append((name, dt_obj))
        
        sorted_period_keys = sorted(grouped_by_period.keys(), reverse=True)
        kept_periods = 0
        for period_key in sorted_period_keys:
            if kept_periods >= count: break
            period_snapshots_sorted = sorted(grouped_by_period[period_key], key=lambda x: x[1], reverse=True)
            if period_snapshots_sorted:
                keep_snapshots_names.add(period_snapshots_sorted[0][0])
                kept_periods += 1

    # Apply retention policies
    for period_name in ['hourly', 'daily', 'weekly', 'monthly', 'yearly']:
        count = retention_policy.get(period_name, 0)
        if count > 0:
            if period_name == 'hourly':   extractor = lambda dt: (dt.year, dt.month, dt.day, dt.hour)
            elif period_name == 'daily':  extractor = lambda dt: (dt.year, dt.month, dt.day)
            elif period_name == 'weekly': extractor = lambda dt: (dt.isocalendar().year, dt.isocalendar().week)
            elif period_name == 'monthly':extractor = lambda dt: (dt.year, dt.month)
            elif period_name == 'yearly': extractor = lambda dt: dt.year
            else: continue # Should not happen
            apply_period_retention(all_snaps_with_dt, count, extractor)

    print(f"\nINFO [{target_name}]: Snapshot Pruning Plan:")
    print(f"  Total snapshots found: {len(all_snaps_with_dt)}")
    print(f"  Snapshots to keep based on policy ({len(keep_snapshots_names)}):")
    for name in sorted(list(keep_snapshots_names), key=lambda n: parse_snapshot_name(n) or datetime.min, reverse=True):
        print(f"    - KEEP: {name}")

    snapshots_to_delete_names = [name for name, dt_obj in all_snaps_with_dt if name not in keep_snapshots_names]

    if not snapshots_to_delete_names:
        print(f"INFO [{target_name}]: No snapshots to delete based on the current retention policy.")
        return

    print(f"  Snapshots to delete ({len(snapshots_to_delete_names)}):")
    for name in sorted(snapshots_to_delete_names, key=lambda n: parse_snapshot_name(n) or datetime.min):
        print(f"    - DELETE: {name}")

    if dry_run:
        print(f"DRY-RUN [{target_name}]: No snapshots will be deleted.")
        return

    proceed_with_deletion = False
    if auto_confirm:
        print(f"INFO [{target_name}]: Auto-confirmation enabled. Proceeding with deletion.")
        proceed_with_deletion = True
    else:
        try:
            confirm = input(f"CONFIRM [{target_name}]: Proceed with deletion of the above listed snapshots? (yes/NO): ")
            if confirm.lower() == 'yes':
                proceed_with_deletion = True
        except EOFError: # Handle non-interactive environments where input() fails
             print(f"WARNING [{target_name}]: Cannot confirm interactively (EOFError). Aborting deletion for this target. Use --yes for non-interactive mode.", file=sys.stderr)
             proceed_with_deletion = False


    if proceed_with_deletion:
        print(f"INFO [{target_name}]: Deleting snapshots...")
        deleted_count = 0
        failed_count = 0
        for snap_name in snapshots_to_delete_names:
            if delete_snapshot_for_target(target_name, parent_subvolume, snapshots_subdir_name, snap_name, dry_run=False):
                deleted_count +=1
            else:
                failed_count +=1
        print(f"INFO [{target_name}]: Pruning complete. Deleted: {deleted_count}, Failed: {failed_count}.")
    else:
        print(f"INFO [{target_name}]: Pruning aborted for this target.")

# --- Configuration Loading ---
def load_configuration(config_path):
    """
    Loads snapshot targets and their configurations from the INI file.
    Each target is expected to be in a section like [target.mydata].
    """
    if not os.path.exists(config_path):
        print(f"ERROR: Configuration file '{config_path}' not found.", file=sys.stderr)
        sys.exit(1)

    config_parser = configparser.ConfigParser(allow_no_value=True, inline_comment_prefixes=('#', ';'))
    # Make parser case-sensitive for section names
    config_parser.optionxform = str 
    try:
        config_parser.read(config_path)
        print(f"INFO: Loaded configuration from: {config_path}")
    except configparser.Error as e:
        print(f"ERROR: Parsing config file '{config_path}': {e}", file=sys.stderr)
        sys.exit(1)

    targets = []
    for section_name in config_parser.sections():
        if section_name.startswith("target."):
            target_name = section_name.split("target.", 1)[1]
            if not target_name:
                print(f"WARNING: Invalid target section name '{section_name}' in config. Skipping.", file=sys.stderr)
                continue

            target_data = dict(config_parser.items(section_name))
            
            # Validate required fields
            parent_subvolume = target_data.get('parent_subvolume')
            if not parent_subvolume:
                print(f"WARNING: Target '{target_name}' is missing 'parent_subvolume'. Skipping.", file=sys.stderr)
                continue
            
            # Ensure parent_subvolume is an absolute path
            if not os.path.isabs(parent_subvolume):
                 print(f"WARNING: Target '{target_name}' has a relative 'parent_subvolume': '{parent_subvolume}'. "
                       "It should be an absolute path. Attempting to resolve, but this may be unreliable.", file=sys.stderr)
                 parent_subvolume = os.path.abspath(parent_subvolume)


            current_target_config = {
                'name': target_name,
                'parent_subvolume': parent_subvolume,
                'snapshots_subdir_name': target_data.get('snapshots_subdir_name', DEFAULT_SNAPSHOTS_SUBDIR_NAME),
                'read_only': config_parser.getboolean(section_name, 'read_only', fallback=True),
                'retention': {
                    'hourly': config_parser.getint(section_name, 'retention_hourly', fallback=0),
                    'daily': config_parser.getint(section_name, 'retention_daily', fallback=0),
                    'weekly': config_parser.getint(section_name, 'retention_weekly', fallback=0),
                    'monthly': config_parser.getint(section_name, 'retention_monthly', fallback=0),
                    'yearly': config_parser.getint(section_name, 'retention_yearly', fallback=0),
                }
            }
            
            # Check if this target is explicitly disabled
            if not config_parser.getboolean(section_name, 'enabled', fallback=True):
                print(f"INFO: Target '{target_name}' is disabled in the configuration. Skipping.")
                continue

            targets.append(current_target_config)
            
    if not targets:
        print("WARNING: No enabled targets found in the configuration file.", file=sys.stderr)
        
    return targets

# --- Main Application Logic ---
def main():
    parser = argparse.ArgumentParser(
        description="Manages bcachefs snapshots for multiple configured targets.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument(
        "--config",
        default=DEFAULT_CONFIG_PATH,
        help="Path to the configuration file."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulate actions without making any changes to the filesystem."
    )

    subparsers = parser.add_subparsers(dest="action", required=True, help="Action to perform")

    # --- Create snapshot action ---
    create_parser = subparsers.add_parser("create", help="Create new snapshots for all enabled targets.")
    # No target-specific CLI args for 'create' anymore, they come from config.

    # --- Prune snapshots action ---
    prune_parser = subparsers.add_parser("prune", help="Prune old snapshots for all enabled targets.")
    prune_parser.add_argument(
        "--yes", "-y",
        action="store_true",
        help="Automatically answer yes to confirmation prompts (e.g., for non-interactive deletion)."
    )
    # No target-specific CLI args for 'prune' anymore.

    args = parser.parse_args()

    if args.dry_run:
        print("\n--- DRY RUN MODE ENABLED: No changes will be made to the filesystem. ---\n")

    # --- Load all target configurations ---
    all_targets = load_configuration(args.config)

    if not all_targets:
        print("No targets to process. Exiting.")
        sys.exit(0) # Not an error, just nothing to do.

    # --- Perform Action for each target ---
    overall_success = True
    if args.action == "create":
        print(f"=== Starting CREATE operation for {len(all_targets)} target(s) ===")
        for target_conf in all_targets:
            if create_snapshot_for_target(target_conf, args.dry_run) is None and not args.dry_run:
                overall_success = False # Mark failure if any snapshot creation fails
        print(f"\n=== CREATE operation finished. Success: {overall_success} ===")

    elif args.action == "prune":
        print(f"=== Starting PRUNE operation for {len(all_targets)} target(s) ===")
        for target_conf in all_targets:
            # prune_snapshots_for_target doesn't explicitly return success/failure for overall script
            # but logs errors per target.
            prune_snapshots_for_target(target_conf, args.dry_run, args.yes)
        print(f"\n=== PRUNE operation finished. Check logs for individual target status. ===")
    
    else:
        parser.print_help()
        sys.exit(1)

    if not overall_success and args.action == "create":
        sys.exit(1) # Exit with error if any creation failed

if __name__ == "__main__":
    main()
