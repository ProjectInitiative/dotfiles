# nom build .\#nixosConfigurations.dinghy.config.system.build.sdImage

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
  hostSSHFile = pkgs.writeText "ssh_host_ed25519_key" config.sensitiveNotSecret.dinghy_private_ssh_key;
  hostSSHPubFile = pkgs.writeText "ssh_host_ed25519_key.pub" config.sensitiveNotSecret.dinghy_public_ssh_key;
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

  hardware.deviceTree.overlays = [
      { name = "gpio"; dtboFile = ./gpio.dtbo; }
    ];

  hardware.rockpi-quad = {
    enable = true;
    # Optional: Customize settings (see flake.nix for options)
    settings = {
      # fan.lv0 = 40;
      # oled."f-temp" = true;
    };
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
    useDHCP = true;
    interfaces = { }; # Clear interfaces - managed by systemd-networkd
    useNetworkd = true;

    # usePredictableInterfaceNames = false;
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
