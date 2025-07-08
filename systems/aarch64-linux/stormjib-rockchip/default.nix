# default.nix
{
  config,
  inputs,
  pkgs,
  lib,
  modulesPath,
  ...
}:
let
  hostSSHFile = pkgs.writeText "ssh_host_ed25519_key" config.sensitiveNotSecret.stormjib_private_ssh_key;
  hostSSHPubFile = pkgs.writeText "ssh_host_ed25519_key.pub" config.sensitiveNotSecret.stormjib_public_ssh_key;

  # ### ADDED: Example of how to specify a custom TPL file if you generated one
  # ### Option 1: You generated it outside Nix and have a path
  # myCustomTpl = /path/to/my/generated_ddr.bin;
  # ### Option 2: You have a ddrbin_param.txt and want Nix to try generating it (EXPERIMENTAL)
  # myDdrParamFile = ./my_e52c_ddrbin_param.txt; # You need to create this file!

in
{
  imports = with inputs.nixos-hardware.nixosModules; [
    (modulesPath + "/installer/scan/not-detected.nix")
    # ### MODIFIED: Pass custom TPL options to rockchip-sd-image.nix
    (import ./rockchip-sd-image.nix {
      inherit config
              lib
              pkgs
              modulesPath;
      # customTplFileForUboot = myCustomTpl; # Uncomment if using Option 1
      # ddrParamFileForUboot = myDdrParamFile; # Uncomment if using Option 2
      # If both are null, uboot-build.nix will use its default generic TPL.
    })
  ];

  home-manager.users.kylepzak.home.stateVersion = "25.05";

  boot = {
    supportedFilesystems.zfs = lib.mkForce false;
    loader = {
      grub.enable = false;
      systemd-boot.enable = false;
      generic-extlinux-compatible.enable = true;
    };
    kernelParams = [
      "nomodeset" # Often needed for initial boot on SBCs if display drivers are tricky
      "keep_bootcon"
    ];
    # kernelPackages = pkgs.linuxPackages_latest; # This is now handled in rockchip-sd-image.nix
  };

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
    hosts.masthead.stormjib.enable = false; # Assuming this is your project-specific module
    networking = {
      tailscale = {
        enable = false;
        ephemeral = false;
        extraArgs = [
          "--accept-dns=false"
        ];
      };
    };
    system = {
      console-info.ip-display.enable = false;
    };
  };

  services.openssh.enable = true;
  console.enable = true; # For serial console access in NixOS
  environment.systemPackages = with pkgs; [
    # Add any essential tools you want in the final image
    vim
    htop
    # rkdeveloptool # If you want this on the device itself
  ];

  # Networking: Your systemd-networkd setup looks reasonable.
  # Ensure the MAC addresses 0a:80:4e:8f:aa:37 and 0e:80:4e:8f:aa:37 are correct for your E52C's interfaces.
  # networking = {
  #   networkmanager.enable = false;
  #   useDHCP = false;
  #   interfaces = { };
  #   useNetworkd = true;
  # };
  # systemd.network = {
  #   enable = true;
  #   # wait-online.enable = false; # Might be useful during debugging if network is slow to come up

  #   links = {
  #     "10-lan" = {
  #       matchConfig.MACAddress = "16:ba:ba:b6:27:7a";
  #       linkConfig.Name = "lan0";
  #     };
  #     "11-wan" = {
  #       matchConfig.MACAddress = "16:ba:ba:b6:27:7b";
  #       linkConfig.Name = "wan0";
  #     };
  #   };
  #   networks = {
  #     "12-lan" = {
  #       matchConfig.Name = "lan0";
  #       networkConfig = {
  #         DHCP = "yes"; # or static IP configuration
  #         IPv6AcceptRA = false; # Explicitly false if you don't want RA
  #       };
  #     };
  #     "13-wan" = {
  #       matchConfig.Name = "wan0";
  #       networkConfig = {
  #         DHCP = "yes"; # or static IP configuration
  #         IPv6AcceptRA = false; # Explicitly false if you don't want RA
  #       };
  #     };
  #   };
  # };

  # Keep tmpfs and journald settings for SD card longevity
  # fileSystems."/tmp" = {
  #   device = "tmpfs";
  #   fsType = "tmpfs";
  #   options = [ "nosuid" "nodev" "relatime" "size=256M" ];
  # };
  # services.journald.extraConfig = ''
  #   Storage=volatile
  #   RuntimeMaxUse=64M
  #   SystemMaxUse=64M
  # '';

}
