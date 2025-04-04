{
  lib,
  pkgs,
  inputs,
  namespace,
  config,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
let
  # Define device paths (replace with actual paths for your hardware)
  bootDevice = "/dev/disk/by-id/nvme-E2M2_64GB_MEK522D002C84"; # Example: 64GB boot drive
  nvmeDevice = "/dev/disk/by-id/nvme-nvme.126f-4141303030303030303030303030303034363434-53504343204d2e32205043496520535344-00000001"; # Example: 1TB NVMe drive

  # Define the bcachefs mountpoint (should match the module option)
  bcachefsMountpoint = "/mnt/pool";
in
{

  # Disko configuration for cargohold
  disko.devices = {
    disk = {
      # Boot Drive Configuration (Classic EXT4)
      boot = {
        type = "disk";
        device = bootDevice;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00"; # EFI System Partition type GUID
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%"; # Use remaining space
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [ "defaults" "noatime" ]; # Example mount options
              };
            };
          };
        };
      };
    nvme1 = {
      type = "disk";
      device = nvmeDevice;
      content = {
        type = "bcachefs_member";
        pool = "pool";
        label = "cache.nvme1";
      };
    };


    hdd1 = {
      type = "disk";
      device = "/dev/disk/by-id/ata-ST6000NM0115-1YZ110_ZAD7GD93";
      content = {
        type = "bcachefs_member";
        pool = "pool";
        label = "hdd.hdd1";
      };
    };
    hdd2 = {
      type = "disk";
      device = "/dev/disk/by-id/ata-ST6000NM0115-1YZ110_ZAD7HEWB";
      content = {
        type = "bcachefs_member";
        pool = "pool";
        label = "hdd.hdd2";
      };
    };

  };


    # Bcachefs Pool Definition
    bcachefs = {
      storage = {
        type = "bcachefs";
        mountpoint = bcachefsMountpoint;
        # Define format options for the pool
        formatOptions = [
          "--compression=none" # Example: Enable LZ4 compression
          "--metadata_replicas=2" # Replicate metadata across 2 devices (e.g., NVMe + one HDD)
          "--data_replicas=2" # Replicate user data across 2 devices (the two HDDs)
          "--data_replicas_required=1" # Allow reading if one data replica is available
          "--foreground_target=cache" # Prefer writing new data to 'fast' label
          "--promote_target=cache" # Promote hot data to 'fast' label
          "--background_target=hdd" # Store bulk data on 'slow' label
        ];
        # Define mount options for the filesystem
        mountOptions = [
          "verbose" # Enable verbose logging during mount
          # "degraded" # Allow mounting in degraded state (use with caution)
        ];
      };
    };
  };

  # Enable the cargohold host configuration
  projectinitiative.hosts.cargohold = {
    enable = true;
    # Override default module options if needed, e.g.:
    # ipAddress = "10.0.0.5/24";
    # interface = "eno1";
    # gateway = "10.0.0.1";
    bcachefsMountpoint = bcachefsMountpoint; # Ensure consistency
  };

  # Basic NixOS settings
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;


}
