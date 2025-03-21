# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).

{ pkgs, ... }:
{
  config = {
    projectinitiative = {
      # hosts.masthead.stormjib.enable = true;
      networking = {
        tailscale.enable = true;
      };
    };

    # Raspberry Pi specific settings
    hardware.raspberry-pi."4".apply-overlays-dtmerge.enable = true;
    hardware.deviceTree.enable = true;

    # Include essential Pi firmware
    hardware.firmware = [ pkgs.raspberrypiWirelessFirmware ];

    # Boot settings for Raspberry Pi
    boot = {
      kernelPackages = pkgs.linuxPackages_rpi4;
      initrd.availableKernelModules = [
        "usbhid"
        "usb_storage"
      ];
      loader = {
        grub.enable = false;
        generic-extlinux-compatible.enable = true;
      };
    };

    services.openssh.enable = true;

    # Use tmpfs for temporary files
    fileSystems."/tmp" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "nosuid"
        "nodev"
        "relatime"
        "size=256M"
      ];
    };

    # journald settings to reduce writes
    services.journald.extraConfig = ''
      Storage=volatile
      RuntimeMaxUse=64M
      SystemMaxUse=64M
    '';

    disko = {
      devices = {
        # Configure for 32GB SD card
        disko.devices.disk.sd.imageSize = "32G";
        disko.devices.disk.sd.imageName = "stormjib-rpi";

        # Cross-compilation settings
        imageBuilder = {
          enableBinfmt = true;
          pkgs = pkgs;
          kernelPackages = pkgs.legacyPackages.x86_64-linux.linuxPackages_latest;
        };
        disk = {
          sd = {
            imageSize = "32G";
            imageName = "stormjib-rpi";
            device = "/dev/mmcblk0";
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                # Boot partition - fixed 256MB size
                boot = {
                  name = "boot";
                  size = "256M"; # Fixed size for boot
                  type = "EF00"; # EFI System Partition
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                    mountOptions = [
                      "defaults"
                      "noatime"
                    ];
                  };
                };

                # Root partition - read-only
                root = {
                  name = "root";
                  size = "20%"; # Percentage of remaining space
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/";
                    mountOptions = [
                      "defaults"
                      "noatime"
                    ]; # "ro" ]; # Read-only mount
                  };
                };

                # Nix store partition
                nix = {
                  name = "nix";
                  size = "35%"; # Percentage of remaining space
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/nix";
                    mountOptions = [
                      "defaults"
                      "noatime"
                    ];
                  };
                };

                # Logs partition
                logs = {
                  name = "logs";
                  size = "10%"; # Percentage of remaining space
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/var/log";
                    mountOptions = [
                      "defaults"
                      "noatime"
                      "commit=600"
                    ];
                  };
                };

                # Persistent data partition
                data = {
                  name = "data";
                  size = "100%"; # Use all remaining space
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/var/lib";
                    mountOptions = [
                      "defaults"
                      "noatime"
                      "commit=600"
                    ];
                  };
                };
              };
            };
          };
        };
      };
    };

  };
}
