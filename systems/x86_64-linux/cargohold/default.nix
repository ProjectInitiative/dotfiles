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
in
{
  hardware.cpu.intel.updateMicrocode = true;


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
                mountOptions = [
                  "defaults"
                  "noatime"
                ]; # Example mount options
              };
            };
          };
        };
      };

      #     hdd1 = {
      #       type = "disk";
      #       device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2EKC1";
      #       content = {
      #         type = "gpt";
      #         partitions = {
      #           hdd1_1 = {
      #             size = "100%";
      #             content = {
      #               type = "bcachefs";
      #               filesystem = "pool"; # Links to bcachefs_filesystems.pool
      #               label = "hdd.hdd1";
      #             };
      #           };
      #         };
      #       };
      #     };

      #     hdd2 = {
      #       type = "disk";
      #       device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZF204VAB";
      #       content = {
      #         type = "gpt";
      #         partitions = {
      #           hdd2_1 = { size = "100%";
      #             content = {
      #               type = "bcachefs";
      #               filesystem = "pool";
      #               label = "hdd.hdd2";
      #             };
      #           };
      #         };
      #       };
      #     };

      #     hdd3 = {
      #       type = "disk";
      #       device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2DTTL";
      #       content = {
      #         type = "gpt";
      #         partitions = {
      #           hdd3_1 = {
      #             size = "100%";
      #             content = {
      #               type = "bcachefs";
      #               filesystem = "pool";
      #               label = "hdd.hdd3";
      #             };
      #           };
      #         };
      #       };
      #     };

      #     hdd4 = {
      #       type = "disk";
      #       device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2EKG5";
      #       content = {
      #         type = "gpt";
      #         partitions = {
      #           hdd4_1 = {
      #             size = "100%";
      #             content = {
      #               type = "bcachefs";
      #               filesystem = "pool";
      #               label = "hdd.hdd4";
      #             };
      #           };
      #         };
      #       };
      #     };

      #     hdd5 = {
      #       type = "disk";
      #       device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2DSW5";
      #       content = {
      #         type = "gpt";
      #         partitions = {
      #           hdd5_1 = {
      #             size = "100%";
      #             content = {
      #               type = "bcachefs";
      #               filesystem = "pool";
      #               label = "hdd.hdd5";
      #             };
      #           };
      #         };
      #       };
      #     };

      #     hdd6 = {
      #       type = "disk";
      #       device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2EMGM";
      #       content = {
      #         type = "gpt";
      #         partitions = {
      #           hdd6_1 = {
      #             size = "100%";
      #             content = {
      #               type = "bcachefs";
      #               filesystem = "pool";
      #               label = "hdd.hdd6";
      #             };
      #           };
      #         };
      #       };
      #     };

      #     nvme1 = {
      #       type = "disk";
      #       device = "/dev/disk/by-id/nvme-nvme.126f-4141303030303030303030303030303034363434-53504343204d2e32205043496520535344-00000001";
      #       content = {
      #         type = "gpt";
      #         partitions = {
      #           nvme1_1 = {
      #             size = "100%";
      #             content = {
      #               type = "bcachefs";
      #               filesystem = "pool";
      #               label = "nvme.nvme1";
      #             };
      #           };
      #         };
      #       };
      #     };
    };

    #   bcachefs_filesystems = {
    #     pool = {
    #       # This name is referenced by the 'filesystem' attribute in partitions
    #       type = "bcachefs_filesystem";
    #       mountpoint = mountpoint; # Your original mountpoint variable
    #       # Updated extraFormatArgs to match the other two configurations
    #       extraFormatArgs = [
    #         "--compression=lz4"
    #         "--foreground_target=nvme" # Targets 'nvme.*' labeled devices
    #         "--background_target=hdd" # Targets 'hdd.*' labeled devices
    #         "--promote_target=ssd" # Will look for 'ssd.*' labeled devices
    #         "--metadata_replicas=2"
    #         "--metadata_replicas_required=1"
    #         "--data_replicas=2"
    #         "--data_replicas_required=1"
    #       ];
    #       mountOptions = [
    #         # Your original mount options
    #         "verbose"
    #         "degraded"
    #         # "fsck"
    #         "nofail"
    #       ];
    #       # As before, if you need specific subvolumes, define them here.
    #       # Otherwise, the entire filesystem is mounted at 'mountpoint'.
    #       # subvolumes = {
    #       #   "subvolumes/some_path" = { mountpoint = "/mnt/some_path"; };
    #       # };
    #     };
    #   };
  };

  projectinitiative.services.bcachefsScrubAuto.enable = mkForce false;
  projectinitiative.services.bcachefsRereplicateAuto.enable = mkForce false;

  swapDevices = [
    {
      device = "/swapfile";
      size = 8 * 1024; # 8GB
    }
  ];

  # boot.kernelParams = [
  #   "cgroup_disable=memory"
  # ];

  # Enable the cargohold host configuration
  projectinitiative.hosts.cargohold = {
    enable = true;
    # Override default module options if needed, e.g.:
    # ipAddress = "10.0.0.5/24";
    # interface = "eno1";
    # gateway = "10.0.0.1";
    bcachefsMountpoint = mountpoint; # Ensure consistency
  };

  # Basic NixOS settings
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

}
