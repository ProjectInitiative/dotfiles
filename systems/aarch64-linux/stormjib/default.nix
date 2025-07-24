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
{
  imports = [
    "${inputs.self}/lib/arm-tools/rockchip-image.nix"
  ];

  # Platform configuration
  nixpkgs.buildPlatform = "x86_64-linux";
  nixpkgs.hostPlatform = "aarch64-linux";

  boot.initrd.availableKernelModules = [
    "dw_mmc_rockchip"  # Specific driver for Rockchip SD/eMMC controllers
    "usbnet" "cdc_ether" "rndis_host" # Drivers for USB-based networking
  ];

  # users.users = {
  #   root = {
  #     # Set the root password to "root" in plaintext
  #     initialPassword = "root";
  #   };
  #   nixos = {
  #     isNormalUser = true;
  #     extraGroups = [ "wheel" ];
  #     # Set the nixos user password to "nixos" in plaintext
  #     initialPassword = "nixos";
  #   };
  # };



  # Rockchip board configuration
  rockchip = {
    enable = true;
    # board = "rk3582-radxa-e52c";
    
    # U-Boot package - will use board default if not specified
    uboot.package = pkgs.uboot-rk3582-generic;
    
    # Device tree - will use board default if not specified
    deviceTree = "rockchip/rk3582-radxa-e52c.dtb";
    
    # Optional: customize console settings (uses board defaults if not specified)
    console = {
      earlycon = "uart8250,mmio32,0xfeb50000";
      console = "ttyS4,1500000";
    };
    
    # Configure which image variants to build
    image.buildVariants = {
      full = true;       # Build full eMMC image with U-Boot (nixos-e52c-full.img)
      sdcard = true;     # Build SD card image without U-Boot (os-only.img)  
      ubootOnly = true;  # Build U-Boot only image
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

  console.enable = true;

    # SSH access
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };
  
  # Enable NetworkManager for easier network setup
  # enP4p65s0 - LAN
  # enP3p49s0 - WAN
  networking = {
    networkmanager = {
        enable = true;
      };
    useDHCP = lib.mkForce true;
  };

  # systemd = {
  #   # Enable networkd
  #   network = {
  #     enable = true;
  #     # wait-online.enable = false; # Disable wait-online to avoid boot delays

  #     # Interface naming based on MAC addresses
  #     links = {
  #       "10-lan" = {
  #         matchConfig.MACAddress = "d8:3a:dd:73:eb:33";
  #         linkConfig.Name = "lan0";
  #       };
  #       "11-wan" = {
  #         matchConfig.MACAddress = "c8:a3:62:b4:ce:fa";
  #         linkConfig.Name = "wan0";
  #       };
  #     };

  #     networks = {
  #       "12-lan" = {
  #         matchConfig.Name = "lan0"; # Match the future name
  #         networkConfig = {
  #           DHCP = "yes";
  #           IPv6AcceptRA = "no";
  #         };
  #       };
  #       "13-wan" = {
  #         matchConfig.Name = "wan0"; # Match the future name
  #         networkConfig = {
  #           DHCP = "yes";
  #           IPv6AcceptRA = "no";
  #         };
  #       };
  #     };
  #   };

  # };
}
