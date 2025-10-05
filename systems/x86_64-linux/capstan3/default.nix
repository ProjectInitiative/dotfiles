{
  config,
  lib,
  namespace,
  options,
  ...
}:
let
  #############################################################################
  #                             1. Core Variables                             #
  #############################################################################
  rootDiskDevicePath = "/dev/disk/by-id/nvme-PM991a_NVMe_Samsung_256GB__S660NX1T487734";
  bcachefsMountpoint = "/mnt/pool";

  #############################################################################
  #                         2. Component Definitions                          #
  #############################################################################
  # --- Common System & Bootloader Config ---
  commonSystemConfig = {
    hardware.cpu.amd.updateMicrocode = true;

    boot.loader = {
      grub = {
        enable = true;
        efiSupport = true;
        efiInstallAsRemovable = true;
        device = "nodev";
      };
      efi.canTouchEfiVariables = false;
    };

    ${namespace}.system = {
      bcachefs-kernel = {
        enable = false;
        debug = true;
      };
      bcachefs-module = {
        enable = false;
        rev = "";
        hash = "";
        debug = true;
      };
    };
  };

  # --- Core Disko Config (Root & Boot only) ---
  coreDiskoConfig = {
    devices = {
      disk.rootSystemDisk = {
        type = "disk";
        device = rootDiskDevicePath;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              name = "ESP";
              type = "EF00";
              size = "512M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            lvm_pv_root = {
              name = "lvm_pv";
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "vgSystem";
              };
            };
          };
        };
      };
      lvm_vg.vgSystem = {
        type = "lvm_vg";
        lvs.lvRoot = {
          name = "root";
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  # --- Bcachefs Disko Config (Data Pool only) ---
  bcachefsDiskoConfig = {
    devices = {
      # disk = {
      #   nvme1 = {
      #     type = "disk";
      #     device = "/dev/disk/by-id/nvme-TEAM_TM8FPD002T_TPBF2310170080200016";
      #     content.partitions.nvme1_1.content = {
      #       type = "bcachefs";
      #       filesystem = "pool";
      #       label = "nvme.nvme1";
      #     };
      #   };
      #   ssd1 = {
      #     type = "disk";
      #     device = "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_AA000000000000000101";
      #     content.partitions.ssd1_1.content = {
      #       type = "bcachefs";
      #       filesystem = "pool";
      #       label = "ssd.ssd1";
      #     };
      #   };
      #   hdd1 = {
      #     type = "disk";
      #     device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2DSW5";
      #     content.partitions.hdd1_1.content = {
      #       type = "bcachefs";
      #       filesystem = "pool";
      #       label = "hdd.hdd1";
      #     };
      #   };
      #   hdd2 = {
      #     type = "disk";
      #     device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2EMGM";
      #     content.partitions.hdd2_1.content = {
      #       type = "bcachefs";
      #       filesystem = "pool";
      #       label = "hdd.hdd2";
      #     };
      #   };
      #   hdd3 = {
      #     type = "disk";
      #     device = "/dev/disk/by-id/ata-ST6000NM0115-1YZ110_ZADABZPK";
      #     content.partitions.hdd3_1.content = {
      #       type = "bcachefs";
      #       filesystem = "pool";
      #       label = "hdd.hdd3";
      #     };
      #   };
      # };
      bcachefs_filesystems.pool = {
        type = "bcachefs_filesystem";
        mountpoint = bcachefsMountpoint;
        extraFormatArgs = [
          "--compression=lz4"
          "--foreground_target=nvme"
          "--background_target=hdd"
          "--promote_target=ssd"
          "--metadata_replicas=2"
          "--metadata_replicas_required=1"
          "--data_replicas=2"
          "--data_replicas_required=1"
        ];
        mountOptions = [
          "verbose"
          "degraded"
          "nofail"
        ];
      };
    };
  };

in
###############################################################################
#                           3. Final Configuration                            #
###############################################################################
lib.recursiveUpdate commonSystemConfig {

  # --- Full System Configuration ---
  disko = lib.recursiveUpdate coreDiskoConfig bcachefsDiskoConfig;

  ${namespace} = {
    suites.attic.enableServer = false;

    hosts.capstan = {
      enable = true;
      # This new flag will control which features are enabled inside the module.
      # You will eventually define this as a proper option in the module itself.
      allFeatures = true;

      # The full configuration is defined once.
      ipAddress = "${config.sensitiveNotSecret.default_subnet}53/24";
      interfaceMac = "7c:10:c9:3c:80:a9";
      bonding = {
        mode = "standard";
        members = [
          "5c:b9:01:e2:6f:d0"
          "5c:b9:01:e2:6f:d4"
        ];
        ipAddress = "172.16.4.53";
      };
      bcachefsInitDevice = "/dev/disk/by-id/nvme-TEAM_TM8FPD002T_TPBF2310170080200016";
      mountpoint = bcachefsMountpoint;
      k8sServerAddr = "https://172.16.1.50:6443";
      k8sNodeIp = "172.16.4.53";
      k8sNodeIface = "bond0";
    };
  };

  # --- Specializations ---
  specialisation.core = {
    configuration = lib.recursiveUpdate commonSystemConfig {
      disko = lib.mkForce coreDiskoConfig;

      # Simply override the one flag for the core specialization.
      # The rest of the host's config (like networking) is inherited.
      ${namespace}.hosts.capstan.allFeatures = lib.mkForce false;
    };
  };
}
