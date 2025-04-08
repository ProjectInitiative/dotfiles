# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).
#
# nom build .\#nixosConfigurations.stormjib.config.system.build.sdImage

{
  config,
  inputs,
  pkgs,
  lib,
  modulesPath,
  ...
}:
let
  # Create files in the nix store
  hostSSHFile = pkgs.writeText "ssh_host_ed25519_key" config.sensitiveNotSecret.stormjib_private_ssh_key;
  hostSSHPubFile = pkgs.writeText "ssh_host_ed25519_key.pub" config.sensitiveNotSecret.stormjib_public_ssh_key;
in
{
  imports = with inputs.nixos-hardware.nixosModules; [
    (modulesPath + "/installer/scan/not-detected.nix")
    # (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    (modulesPath + "/installer/sd-card/sd-image-aarch64-new-kernel.nix")
    # raspberry-pi-4
  ];

  boot.supportedFilesystems.zfs = lib.mkForce false;

  sdImage.compressImage = false;
  

  environment.etc = {
    "ssh/ssh_host_ed25519_key" = {
      source = hostSSHFile;
      mode = "0600";
      user = "root";
      group = "root";
    };

    "ssh/ssh_host_ed25519_key.pub" = {
      source = hostSSHPubFile;
      mode = "0644";
      user = "root";
      group = "root";
    };
  };

  projectinitiative = {
    hosts.masthead.stormjib.enable = true;
    networking = {
      tailscale = {
        enable = true;
        ephemeral = false;
        extraArgs = [
          "--accept-dns=false"
        ];
      };
    };
    system = {
      console-info.ip-display.enable = true;
    };
  };

  # boot.loader = {
  #   grub.enable = false;
  #   systemd-boot.enable = false;  # Disable systemd-boot
  #   generic-extlinux-compatible.enable = true;  # Enable extlinux bootloader
  # };

  services.openssh.enable = true;
  console.enable = true;
  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
  ];
  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
  ];

  # Single networking attribute set
  networking = {
    networkmanager = {
      enable = false;
      wifi.powersave = false;
    };
    useDHCP = false;
    interfaces = { }; # Clear interfaces - managed by systemd-networkd
    useNetworkd = true;

    # usePredictableInterfaceNames = false;
  };

  systemd = {
    # Enable networkd
    network = {
      enable = true;
      # wait-online.enable = false; # Disable wait-online to avoid boot delays

      # Interface naming based on MAC addresses
      links = {
        "10-lan" = {
          matchConfig.MACAddress = "d8:3a:dd:73:eb:33";
          linkConfig.Name = "lan0";
        };
        "11-wan" = {
          matchConfig.MACAddress = "c8:a3:62:b4:ce:fa";
          linkConfig.Name = "wan0";
        };
      };

      networks = {
        "12-lan" = {
          matchConfig.Name = "lan0"; # Match the future name
          networkConfig = {
            DHCP = "yes";
            IPv6AcceptRA = "no";
          };
        };
        "13-wan" = {
          matchConfig.Name = "wan0"; # Match the future name
          networkConfig = {
            DHCP = "yes";
            IPv6AcceptRA = "no";
          };
        };
      };

    };
  };
  # Use tmpfs for temporary files
  # fileSystems."/tmp" = {
  #   device = "tmpfs";
  #   fsType = "tmpfs";
  #   options = [
  #     "nosuid"
  #     "nodev"
  #     "relatime"
  #     "size=256M"
  #   ];
  # };

  # journald settings to reduce writes
  # services.journald.extraConfig = ''
  #   Storage=volatile
  #   RuntimeMaxUse=64M
  #   SystemMaxUse=64M
  # '';

  # disko = {
  #   devices = {

  #     # Cross-compilation settings
  #     # imageBuilder = {
  #     #   enableBinfmt = true;
  #     #   pkgs = pkgs;
  #     #   kernelPackages = pkgs.legacyPackages.x86_64-linux.linuxPackages_latest;
  #     # };
  #     disk = {
  #       sd = {
  #         imageSize = "32G";
  #         imageName = "stormjib-rpi";
  #         device = "/dev/mmcblk0";
  #         type = "disk";
  #         content = {
  #           type = "gpt";
  #           partitions = {
  #             # Boot partition - fixed 256MB size
  #             boot = {
  #               name = "boot";
  #               size = "256M"; # Fixed size for boot
  #               type = "EF00"; # EFI System Partition
  #               content = {
  #                 type = "filesystem";
  #                 format = "vfat";
  #                 mountpoint = "/boot";
  #                 mountOptions = [
  #                   "defaults"
  #                   "noatime"
  #                 ];
  #               };
  #             };

  #             # Root partition - read-only
  #             root = {
  #               name = "root";
  #               size = "20%"; # Percentage of remaining space
  #               content = {
  #                 type = "filesystem";
  #                 format = "ext4";
  #                 mountpoint = "/";
  #                 mountOptions = [
  #                   "defaults"
  #                   "noatime"
  #                 ]; # "ro" ]; # Read-only mount
  #               };
  #             };

  #             # Nix store partition
  #             nix = {
  #               name = "nix";
  #               size = "35%"; # Percentage of remaining space
  #               content = {
  #                 type = "filesystem";
  #                 format = "ext4";
  #                 mountpoint = "/nix";
  #                 mountOptions = [
  #                   "defaults"
  #                   "noatime"
  #                 ];
  #               };
  #             };

  #             # Logs partition
  #             logs = {
  #               name = "logs";
  #               size = "10%"; # Percentage of remaining space
  #               content = {
  #                 type = "filesystem";
  #                 format = "ext4";
  #                 mountpoint = "/var/log";
  #                 mountOptions = [
  #                   "defaults"
  #                   "noatime"
  #                   "commit=600"
  #                 ];
  #               };
  #             };

  #             # Persistent data partition
  #             data = {
  #               name = "data";
  #               size = "100%"; # Use all remaining space
  #               content = {
  #                 type = "filesystem";
  #                 format = "ext4";
  #                 mountpoint = "/var/lib";
  #                 mountOptions = [
  #                   "defaults"
  #                   "noatime"
  #                   "commit=600"
  #                 ];
  #               };
  #             };
  #           };
  #         };
  #       };
  #     };
  #   };
  # };

}
