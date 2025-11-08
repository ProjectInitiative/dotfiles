# Sync-Host Module

The sync-host module provides automated backup functionality for the cargohold host, with power management features to save energy and provide a pseudo air-gap backup solution.

## Features

- Automated synchronization of rclone remotes (S3 buckets, etc.)
- Power management with RTC wake functionality
- bcachefs snapshot integration 
- Service dependency checking before shutdown
- Concurrent sync operations for efficiency

## Configuration

### Basic Configuration

```nix
services.sync-host = {
  enable = true;
  rcloneRemotes = [
    "s3-remote:bucket-name/path"
    "gcs-remote:bucket-name/path"
    # Add more remotes as needed
  ];
  rcloneConfig = ''
    [s3-remote]
    type = s3
    provider = AWS
    env_auth = true
    region = us-east-1

    [gcs-remote]
    type = google cloud storage
    # ... configuration
  '';
  powerOff = true; # Power off after sync completion
  wakeUpDelay = "24h"; # Wake up every 24 hours
  localTargetPath = "/mnt/storage/backups";
  bcachefsMountpoint = "/mnt/storage";
};
```

### Options

#### `enable`
- **Type**: `bool`
- **Default**: `false`
- **Description**: Enable the sync-host service

#### `rcloneRemotes`
- **Type**: `list of strings`
- **Default**: `[]`
- **Description**: List of rclone remotes to sync from (format: `"remote-name:remote-path"`)

#### `rcloneConfig`
- **Type**: `string`
- **Default**: `""`
- **Description**: Rclone configuration content

#### `powerOff`
- **Type**: `bool`
- **Default**: `true`
- **Description**: Whether to power off the machine after sync completion

#### `disableRTCWake`
- **Type**: `bool`
- **Default**: `false`
- **Description**: Disable RTC wake functionality for manual debugging

#### `wakeUpTime`
- **Type**: `string`
- **Default**: `"*-*-* 02:00:00"`
- **Description**: Time to wake up the machine in systemd calendar format (only used if powerOff is false)

#### `wakeUpDelay`
- **Type**: `string`
- **Default**: `"24h"`
- **Description**: Delay before next wake-up (e.g., '24h', '7d')

#### `localTargetPath`
- **Type**: `string`
- **Default**: `"/mnt/storage/backups"`
- **Description**: Local target path for sync operations

#### `maxWorkers`
- **Type**: `int`
- **Default**: `4`
- **Description**: Maximum number of concurrent sync operations

#### `bcachefsMountpoint`
- **Type**: `string`
- **Default**: `"/mnt/storage"`
- **Description**: Mount point for bcachefs filesystem where snapshots will be taken

#### `preSyncScripts`
- **Type**: `list of strings`
- **Default**: `[]`
- **Description**: List of scripts to run before the sync

#### `postSyncScripts`
- **Type**: `list of strings`
- **Default**: `[]`
- **Description**: List of scripts to run after the sync

#### `backupTasks`
- **Type**: `list of attrs`
- **Default**: `[]`
- **Description**: List of additional backup tasks to run

#### `telegram.enable`
- **Type**: `bool`
- **Default**: `false`
- **Description**: Enable Telegram notifications for sync-host.

#### `telegram.tokenPath`
- **Type**: `path`
- **Description**: Path to the file containing the Telegram bot token.

#### `telegram.chatIdPath`
- **Type**: `path`
- **Description**: Path to the file containing the Telegram chat ID.

## Operation

The sync-host service implements the following workflow:

1. Powers on the system via RTC wake
2. Runs any pre-sync scripts
3. Performs concurrent rclone sync operations from specified remotes
4. Triggers a bcachefs snapshot of the storage pool
5. Waits for any running bcachefs services (scrub, snapshot creation/pruning) to complete
6. Schedules the next wake-up time using rtcwake
7. Powers off the system

## Security and Safety Features

- The system waits for bcachefs services (scrub, snapshot creation/pruning) to complete before shutting down
- Power management helps reduce idle power consumption (~50W)
- Pseudo air-gap backup solution (only online during sync operations)
- Configurable wake intervals for scheduled backups

## Specialization for Manual Debugging

A specialization called `manual-debug` has been added to the cargohold hardware configuration that:

- Sets `services.sync-host.disableRTCWake = true`
- Sets `services.sync-host.powerOff = false`
- This prevents automatic shutdown, allowing manual access for debugging

To boot into the manual-debug specialization:
1. At boot time, select the "manual-debug" option from the boot menu
2. The system will run the sync operations without powering off
3. You'll have full access to the system for debugging and maintenance