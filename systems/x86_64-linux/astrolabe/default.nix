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

    boot.initrd.systemd.enable = true;

    # 2. Ensure bcachefs is explicitly supported in the early ramdisk.
    boot.initrd.supportedFilesystems = [ "bcachefs" ];
    boot.initrd.kernelModules = [ "bcachefs" ];

    # 3. Update the /nix mount entry.
    fileSystems."/nix" = {
      # UUID is generally more stable than mapper paths in a systemd-initrd.
      device = "UUID=205123cd-4af7-4f23-85d8-44e0fa2f1774";
      fsType = "bcachefs";
      # Use the working community standard for subvolumes.
      options = [
        "X-mount.subdir=nix"
        "noatime"
        "discard"
      ];
      neededForBoot = true;
    };
    fileSystems."/home/kylepzak" = {
      # UUID is generally more stable than mapper paths in a systemd-initrd.
      device = "UUID=205123cd-4af7-4f23-85d8-44e0fa2f1774";
      fsType = "bcachefs";
      # Use the working community standard for subvolumes.
      options = [
        "X-mount.subdir=home/kylepzak"
        "noatime"
        "discard"
      ];
    };

    # Force LVM to settle before bcachefs attempts to mount
    boot.initrd.services.lvm.enable = true;

    boot.loader = {
      systemd-boot.enable = true;
      systemd-boot.configurationLimit = 4;
      efi.canTouchEfiVariables = true;
    };

    # Ensure kernel is 7 rc
    boot.kernelPackages = upstream.linuxPackages_testing;

    # Pull bleeding-edge Mesa (Vulkan) drivers from master for the Strix Halo
    hardware.graphics = {
      enable = true;
      package = upstream.mesa;
      package32 = upstream.pkgsi686Linux.mesa;
    };

    # ROCm nightly overlay — builds rocmPackages from ROCm's develop branch
    # nixpkgs.overlays = [ inputs.nix-amd-ai.overlays.rocm-nightly ];

    hardware.amd-npu = {
      enable = true;
      enableNPU = true;         # default; set false for GPU-only hosts (see "Other hardware")
      enableFastFlowLM = true;  # LLM inference on NPU (requires enableNPU)
      enableLemonade = true;    # OpenAI-compatible API server
      enableROCm = true;        # ROCm GPU backends (llamacpp + sd-cpp)
      useRocmNightly = true;    # build ROCm from rocm-systems develop branch
      enableVulkan = true;      # Vulkan GPU backends (llamacpp + whispercpp)
      enableImageGen = true;    # default true; set false to drop sd-cpp from closure
      lemonade.user = "kylepzak";
      lemonade.host = "0.0.0.0";
      lemonade.maxLoadedModels = 4;
    };
    systemd.services.lemond.environment = {
      HF_HOME = "/mnt/pool/ai/huggingface";
      XDG_CACHE_HOME = "/mnt/pool/ai/huggingface";
    };

    boot.extraModulePackages = [ config.boot.kernelPackages.r8125 ];
    boot.blacklistedKernelModules = [ "r8169" ];

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
            # REMOVE the mountpoint here for now to avoid Stage 1 conflicts
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

    backupFileExtension = "backup";

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
    services = {
      bcachefsSnapshots = {
        targets = {

          void = {
            parentSubvolume = "/mnt/pool/home"; # MANDATORY: Set path for this new target
            readOnlySnapshots = true; # Optional: default is true

            retention = {
              # Define retention for this new target
              hourly = 6;
              daily = 7;
              weekly = 4;
              monthly = 6;
              yearly = 2;
            };
          };
        };
      };
    };

    hosts.astrolabe = {
      enable = true;
      allFeatures = true;

      ipAddress = "${config.sensitiveNotSecret.default_subnet}54/24";
      vlanIpAddress = "172.16.4.54/24";
      vlanId = 10;
      interfaceMac = "84:47:09:75:04:61";

      k8sServerAddr = "https://172.16.1.50:6443";
      k8sNodeIp = "172.16.4.54";
      k8sNodeIface = "mgmnt.10";
    };
  };
}
