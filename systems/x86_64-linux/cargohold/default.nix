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
  bootDevice = "/dev/sda"; # Example: 64GB boot drive
  nvmeDevice = "/dev/nvme0n1"; # Example: 1TB NVMe drive
  hddDevice1 = "/dev/sdb"; # Example: First HDD
  hddDevice2 = "/dev/sdc"; # Example: Second HDD

  # Define the bcachefs mountpoint (should match the module option)
  bcachefsMountpoint = "/mnt/storage";
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

      # NVMe Drive (Bcachefs Fast Tier)
      nvme = {
        type = "disk";
        device = nvmeDevice;
        content = {
          type = "gpt";
          partitions = {
            bcachefs_fast = {
              size = "100%";
              content = {
                type = "bcachefs_member";
                pool = "storage";
                label = "fast";
                # Consider specifying allowed data types for optimization
                # dataAllowed = [ "journal" "btree" ];
                discard = true; # Enable discard/TRIM if supported
              };
            };
          };
        };
      };

      # First HDD (Bcachefs Slow Tier)
      hdd1 = {
        type = "disk";
        device = hddDevice1;
        content = {
          type = "gpt";
          partitions = {
            bcachefs_slow1 = {
              size = "100%";
              content = {
                type = "bcachefs_member";
                pool = "storage";
                label = "slow";
                durability = 2; # Part of the mirrored data set
                dataAllowed = [ "user" ]; # Store user data here
              };
            };
          };
        };
      };

      # Second HDD (Bcachefs Slow Tier)
      hdd2 = {
        type = "disk";
        device = hddDevice2;
        content = {
          type = "gpt";
          partitions = {
            bcachefs_slow2 = {
              size = "100%";
              content = {
                type = "bcachefs_member";
                pool = "storage";
                label = "slow";
                durability = 2; # Part of the mirrored data set
                dataAllowed = [ "user" ]; # Store user data here
              };
            };
          };
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
          "--compression=lz4" # Example: Enable LZ4 compression
          "--metadata_replicas=2" # Replicate metadata across 2 devices (e.g., NVMe + one HDD)
          "--data_replicas=2" # Replicate user data across 2 devices (the two HDDs)
          "--data_replicas_required=1" # Allow reading if one data replica is available
          "--foreground_target=fast" # Prefer writing new data to 'fast' label
          "--promote_target=fast" # Promote hot data to 'fast' label
          "--background_target=slow" # Store bulk data on 'slow' label
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

  networking.hostName = "cargohold"; # Set the hostname

  # Define users (replace with your actual user)
  users.users.kyle = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ]; # Add necessary groups
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH..."
    ];
  };

  # Allow unfree packages if needed (e.g., for certain firmware)
  nixpkgs.config.allowUnfree = true;

  # Set the system state version
  system.stateVersion = "24.05"; # Or your desired version
}
