{
  config,
  lib,
  namespace,
  options,
  ...
}:
let
  mountpoint = "/mnt/pool";
  rootDiskDevicePath = "/dev/disk/by-id/nvme-PM991a_NVMe_Samsung_256GB__S660NE1R749627";
in
{
  ${namespace} = {

    system = {
      bcachefs-kernel = {
        enable = true;
        # rev = "";
        # hash = "";
        debug = true;
      };
      bcachefs-module = {
        enable = false;
        rev = ""; # Or specify a specific commit hash
        hash = "";
        debug = true;
      };
    };

    hosts.capstan = {
      enable = true;
      ipAddress = "${config.sensitiveNotSecret.default_subnet}51/24";
      interface = "enp4s0";
      enableMlx = true;
      mlxIpAddress = "172.16.4.51";
      mlxPcie = "0000:06:00.0";
      bondMembers = [
        "enp6s0"
        "enp6s0d1"
      ];
      bcachefsInitDevice = "/dev/disk/by-id/nvme-TEAM_TM8FPD002T_TPBF2310170080206935";
      mountpoint = mountpoint;
      k8sServerAddr = "https://172.16.1.52:6443";
    };

  };

   disko = {
     devices = {
       disk = {

          rootSystemDisk = {
            type = "disk";
            device = rootDiskDevicePath;
            content = {
              type = "gpt";
              partitions = {
                # EFI System Partition (ESP) for booting
                ESP = {
                  name = "ESP"; # Partition label
                  type = "EF00"; # Standard EFI partition type
                  size = "512M";
                  content = {
                    type = "filesystem";
                    format = "vfat"; # FAT32 for ESP
                    mountpoint = "/boot"; # Common mountpoint for ESP, especially with systemd-boot
                  };
                };
                # Partition for LVM Physical Volume
                lvm_pv_root = {
                  name = "lvm_pv"; # Partition label
                  size = "100%"; # Use the rest of the disk
                  content = {
                    type = "lvm_pv";
                    vg = "vgSystem"; # This PV will belong to the 'vgSystem' Volume Group
                  };
                };
              };
            };
          };
      
         # nvme1 = {
         #   type = "disk";
         #   device = "/dev/disk/by-id/nvme-TEAM_TM8FPD002T_TPBF2310170080206935";
         #   content = {
         #     type = "gpt";
         #     partitions = {
         #       nvme1_1 = {
         #         # You can name this partition descriptively
         #         size = "100%";
         #         content = {
         #           type = "bcachefs";
         #           filesystem = "pool"; # Refers to the bcachefs_filesystem defined below
         #           label = "nvme.nvme1"; # Original label for bcachefs device
         #         };
         #       };
         #     };
         #   };
         # };

         # ssd1 = {
         #   type = "disk";
         #   device = "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_2020080200277";
         #   content = {
         #     type = "gpt";
         #     partitions = {
         #       ssd1_1 = {
         #         size = "100%";
         #         content = {
         #           type = "bcachefs";
         #           filesystem = "pool";
         #           label = "ssd.ssd1";
         #         };
         #       };
         #     };
         #   };
         # };

         # hdd1 = {
         #   type = "disk";
         #   device = "/dev/disk/by-id/ata-ST6000VN001-2BB186_ZR10KV5V";
         #   content = {
         #     type = "gpt";
         #     partitions = {
         #       hdd1_1 = {
         #         size = "100%";
         #         content = {
         #           type = "bcachefs";
         #           filesystem = "pool";
         #           label = "hdd.ZR10KV5V";
         #         };
         #       };
         #     };
         #   };
         # };

       #   hdd2 = {
       #     type = "disk";
       #     device = "/dev/disk/by-id/";
       #     content = {
       #       type = "gpt";
       #       partitions = {
       #         hdd2_1 = {
       #           size = "100%";
       #           content = {
       #             type = "bcachefs";
       #             filesystem = "pool";
       #             label = "hdd.hdd2";
       #           };
       #         };
       #       };
       #     };
       #   };

       #   hdd3 = {
       #     type = "disk";
       #     device = "/dev/disk/by-id/";
       #     content = {
       #       type = "gpt";
       #       partitions = {
       #         hdd3_1 = {
       #           size = "100%";
       #           content = {
       #             type = "bcachefs";
       #             filesystem = "pool";
       #             label = "hdd.hdd3";
       #           };
       #         };
       #       };
       #     };
       #   };
       };
        # == LVM Volume Group and Logical Volume Definitions ==
        lvm_vg = {
          vgSystem = { # Name of the Volume Group for the system
            type = "lvm_vg";
            # 'pvs' attribute is automatically determined from partitions using this VG.
            lvs = {
              # Logical Volume for the root filesystem
              lvRoot = {
                name = "root"; # Name of the LV
                size = "100%FREE"; # Use all available space in this VG for root.
                                   # Or specify a fixed size like "50G".
                content = {
                  type = "filesystem";
                  format = "ext4"; # Format as ext4
                  mountpoint = "/";  # Mount as the root filesystem
                  # mountOptions = [ "defaults", "noatime" ]; # Optional: specify mount options
                };
              };
              # Example: You could add a swap LV here if needed
              # lvSwap = {
              #   type = "lvm_lv";
              #   name = "swap";
              #   size = "8G"; # Example size for swap
              #   content = {
              #     type = "swap";
              #   };
              # };
            };
          };
        }; # End of 'lvm_vg' section

       # bcachefs_filesystems = {
       #   pool = {
       #     # This name ("pool") links the partitions above to this definition
       #     type = "bcachefs_filesystem";
       #     mountpoint = mountpoint; # Preserving the variable reference from your source
       #     # Global format options for the bcachefs filesystem
       #     extraFormatArgs = [
       #       "--compression=lz4"
       #       "--foreground_target=nvme" # These targets refer to the labels (e.g., "nvme.nvme1" will match "nvme")
       #       "--background_target=hdd"
       #       "--promote_target=ssd"
       #       "--metadata_replicas=2"
       #       "--metadata_replicas_required=1"
       #       "--data_replicas=2"
       #       "--data_replicas_required=1"
       #     ];
       #     mountOptions = [
       #       "verbose"
       #       "degraded"
       #       "fsck"
       #       "nofail"
       #     ];
       #     # Since your original config doesn't specify subvolumes for the pool,
       #     # we assume the entire filesystem is mounted at `mountpoint`.
       #     # If you need specific subvolumes, you would define them here, similar to the example:
       #     # subvolumes = {
       #     #   "subvolumes/root" = { mountpoint = "/"; };
       #     #   # ... other subvolumes
       #     # };
       #   };
       # };
     };
   };

  # == GRUB Bootloader Configuration ==
  # These settings configure GRUB for an EFI system with an LVM root.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;          # Enable EFI support
    efiInstallAsRemovable = true; # Installs GRUB to the fallback path, often more compatible
    device = "nodev";  # Install GRUB on this disk (must match disko's rootSystemDisk.device)
    # device = "${rootDiskDevicePath}";  # Install GRUB on this disk (must match disko's rootSystemDisk.device)
  };

  # This allows NixOS to manage EFI boot entries.
  boot.loader.efi.canTouchEfiVariables = false;

  # Optional: If your ESP is not at /boot, specify it. Disko sets it to /boot.
  # boot.loader.efi.efiSysMountPoint = "/boot";
  

}
