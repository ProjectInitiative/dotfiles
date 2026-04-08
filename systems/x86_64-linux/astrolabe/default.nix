{
  config,
  lib,
  namespace,
  options,
  upstream,
  inputs,
  ...
}:
let
  #############################################################################
  #                             1. Core Variables                             #
  #############################################################################
  # Update to actual path later if needed. Use a dummy device for now
  rootDiskDevicePath = "/dev/nvme0n1";
  bcachefsMountpoint = "/mnt/pool";

  #############################################################################
  #                         2. Component Definitions                          #
  #############################################################################
  # --- Common System & Bootloader Config ---
  commonSystemConfig = {
    boot.loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Ensure kernel is 7 rc
    boot.kernelPackages = upstream.linuxPackages_testing;

    # Pull bleeding-edge Mesa (Vulkan) drivers from master for the Strix Halo
    hardware.graphics = {
      enable = true;
      package = upstream.mesa.drivers;
      package32 = upstream.pkgsi686Linux.mesa.drivers;
    };

    # Pull bleeding-edge linux-firmware (optional, but highly recommended for new APUs)
    hardware.firmware = [ upstream.linux-firmware ];

    services.journald.extraConfig = "Storage=volatile\n";

    projectinitiative = {
      encrypted.nix-signing.enable = true;
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
          size = "100G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [
              "noatime"
              "nodiratime"
              "discard"
            ];
          };
        };
        lvs.lvData = {
          name = "data";
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "bcachefs";
            mountpoint = bcachefsMountpoint;
          };
        };
      };
    };
  };

in
###############################################################################
#                           3. Final Configuration                            #
###############################################################################
lib.recursiveUpdate commonSystemConfig {

  # --- Full System Configuration ---
  disko = coreDiskoConfig;

  home-manager = {

    users.kylepzak.${namespace} = {
      suites = {
        development.enable = true;
      };
    };

  };

  ${namespace} = {
    suites = {
      loft = {
        enableServer = true;
      };
    };

    hosts.astrolabe = {
      enable = true;
      allFeatures = true;

      ipAddress = "${config.sensitiveNotSecret.default_subnet}54/24";
      interfaceMac = "84:47:09:75:04:61";

      k8sServerAddr = "https://172.16.1.50:6443";
      k8sNodeIp = "172.16.1.54";
      k8sNodeIface = "mgmnt";
    };
  };
}
