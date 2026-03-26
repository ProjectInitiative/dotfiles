{
  config,
  lib,
  namespace,
  options,
  pkgs,
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
    hardware.cpu.amd.updateMicrocode = true;

    boot.loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Ensure kernel is 6.18+ (currently using latest)
    # The requirement says `set the kernel to 6.18+`
    # You can set it to `linuxPackages_latest` to get the latest stable, which should be >=6.18
    # Or explicitly pin if 6.18 is available.
    # boot.kernelPackages = pkgs.linuxPackages_latest;

    boot.kernelPackages = pkgs.linuxPackages_6_18; # Will verify if this exists or just use latest

    # VRAM Unlock
    boot.kernelParams = [ "amdgpu.gttsize=-1" ];

    hardware.graphics = {
      enable = true;
      # ROCm and VA-API
      extraPackages = with pkgs; [
        rocmPackages.clr
        rocmPackages.clr.icd
        # VA-API
        libvdpau-va-gl
      ];
    };

    # KFD driver initialization is part of amdgpu kernel module
    boot.initrd.kernelModules = [ "amdgpu" ];

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
            type = "bcachefs";
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

      ipAddress = "${config.sensitiveNotSecret.default_subnet}52/24";
      interfaceMac = "11:22:33:44:55:66";

      k8sServerAddr = "https://172.16.1.50:6443";
      k8sNodeIp = "172.16.4.52";
      k8sNodeIface = "mgmnt";
    };
  };
}
