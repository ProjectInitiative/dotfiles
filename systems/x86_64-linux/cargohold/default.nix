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
  mountpoint = "/mnt/pool";

  #############################################################################
  #                         Component Definitions                             #
  #############################################################################

  # --- Common System Config ---
  commonSystemConfig = {
    hardware.cpu.intel.updateMicrocode = true;

    # Basic NixOS settings
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    swapDevices = [
      {
        device = "/swapfile";
        size = 8 * 1024; # 8GB
      }
    ];
  };

  # --- Core Disko Config (Boot & Root only) ---
  coreDiskoConfig = {
    devices = {
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
                  mountOptions = [
                    "defaults"
                    "noatime"
                  ]; # Example mount options
                };
              };
            };
          };
        };
      };
    };
  };

  # --- Bcachefs Disko Config (Data Pool only) ---
  bcachefsDiskoConfig = {
    devices = {
      bcachefs_filesystems = {
        pool = {
          # This name is referenced by the 'filesystem' attribute in partitions
          type = "bcachefs_filesystem";
          mountpoint = mountpoint; # Your original mountpoint variable
          # Updated extraFormatArgs to match the other two configurations
          extraFormatArgs = [
            "--compression=lz4"
            "--foreground_target=nvme" # Targets 'nvme.*' labeled devices
            "--background_target=hdd" # Targets 'hdd.*' labeled devices
            "--promote_target=ssd" # Will look for 'ssd.*' labeled devices
            "--metadata_replicas=2"
            "--metadata_replicas_required=1"
            "--data_replicas=2"
            "--data_replicas_required=1"
          ];
          mountOptions = [
            # Your original mount options
            "verbose"
            "degraded"
            # "fsck"
            "nofail"
          ];
        };
      };
    };
  };

in
###############################################################################
#                           Final Configuration                               #
###############################################################################
lib.recursiveUpdate commonSystemConfig {

  # --- Full System Configuration ---
  disko = lib.recursiveUpdate coreDiskoConfig bcachefsDiskoConfig;

  projectinitiative.services.bcachefsScrubAuto.enable = mkForce false;
  projectinitiative.services.bcachefsRereplicateAuto.enable = mkForce false;

  # Enable the cargohold host configuration
  projectinitiative.hosts.cargohold = {
    enable = true;
    # Override default module options if needed, e.g.:
    # ipAddress = "10.0.0.5/24";
    # interface = "eno1";
    # gateway = "10.0.0.1";
    bcachefsMountpoint = mountpoint; # Ensure consistency
  };

  # --- Specializations ---
  specialisation.core = {
    configuration = lib.recursiveUpdate commonSystemConfig {
      disko = lib.mkForce coreDiskoConfig;

      # Keep the cargohold module enabled but potentially disable bcachefs-related features
      # You may want to add a flag to the cargohold module similar to capstan's allFeatures
      projectinitiative.hosts.cargohold = {
        enable = true;
        bcachefsMountpoint = lib.mkForce null; # Disable bcachefs mountpoint in core mode
      };

      # Ensure bcachefs services are disabled in core specialization
      projectinitiative.services.bcachefsScrubAuto.enable = mkForce false;
      projectinitiative.services.bcachefsRereplicateAuto.enable = mkForce false;
    };
  };
}
