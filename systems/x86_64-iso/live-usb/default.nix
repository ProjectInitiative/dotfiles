{
  lib,
  inputs,
  config,
  namespace,
  modulesPath,
  pkgs,
  options,
  ...
}:
with lib;
with lib.${namespace};
let
  hostname = "live-iso";
  nixRev = if inputs.nixpkgs ? rev then inputs.nixpkgs.shortRev else "dirty";
  selfRev = if inputs.self ? rev then inputs.self.shortRev else "dirty";
in
{
  imports = [
    # base profiles
    "${modulesPath}/profiles/base.nix"
    "${modulesPath}/profiles/all-hardware.nix"

    # Let's get it booted in here
    "${modulesPath}/installer/cd-dvd/iso-image.nix"

    # Provide an initial copy of the NixOS channel so that the user
    # doesn't need to run "nix-channel --update" first.
    "${modulesPath}/installer/cd-dvd/channel.nix"

    # Add compatible kernel
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal-new-kernel-no-zfs.nix"

  ];

  config = {

    # Run through tor because finger printing or something? Supposed to be
    # relatively amnesiac.
    # services.tor = {
    #   enable = false;
    #   client = {
    #     enable = true;
    #     dns.enable = true;
    #     transparentProxy.enable = true;
    #   };
    # };

    # Enable networking
    # networking = mkforce {
    #   networkmanager.enable = true;  # enable networkmanager
    #   usedhcp = true;               # enable dhcp globally
    # };

    programs.zsh.enable = true;
    # Disable password authentication globally
    users.mutableUsers = false;
    # Enable auto-login for console
    services.getty.autologinUser = mkForce "root";

    # If you're using display manager (like SDDM, GDM, etc), configure auto-login there too
    services.displayManager.autoLogin = {
      enable = true;
      user = "root";
    };

    # ISO naming.
    isoImage.isoName = mkForce "NixOS-${hostname}-${nixRev}-${selfRev}.iso";

    # EFI + USB bootable
    isoImage.makeEfiBootable = true;
    isoImage.makeUsbBootable = true;

    boot.supportedFilesystems = [ "bcachefs" ];
    boot.kernelPackages = lib.mkOverride 0 pkgs.linuxPackages_latest;

    # Other cases
    isoImage.appendToMenuLabel = " live";
    # isoImage.contents = [{
    #   source = "/path/to/source/file";
    #   target = "/path/in/iso";
    # }];
    # isoFileSystems <- add luks (see issue dmadisetti/#34)
    # boot.loader = rec {
    #   grub2-theme = {
    #     enable = true;
    #     icon = "";
    #     theme = "";
    #     screen = "1080p";
    #     splashImage = ../../dot/backgrounds/live.png;
    #     footer = true;
    #   };
    # };
    # isoImage.grubTheme = config.boot.loader.grub.theme;
    isoImage.splashImage = config.boot.loader.grub.splashImage;
    isoImage.efiSplashImage = config.boot.loader.grub.splashImage;

    # Add Memtest86+ to the ISO.
    boot.loader.grub.memtest86.enable = true;

    console.enable = true;
    # enable GPU drivers
    hardware.enableRedistributableFirmware = true;
    hardware.firmware = [ pkgs.linux-firmware ];
    # An installation media cannot tolerate a host config defined file
    # system layout on a fresh machine, before it has been formatted.
    swapDevices = mkImageMediaOverride [ ];
    fileSystems = mkImageMediaOverride config.lib.isoFileSystems;

  };

  # ${namespace} = {
  #   hosts.live-usb = {
  #     enable = true;
  #   };
  # };
}
