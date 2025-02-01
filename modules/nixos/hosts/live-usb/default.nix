{ lib, inputs, config, namespace, modulesPath, options, ... }:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.live-usb;
  hostname = "live-iso";
  nixRev =
    if inputs.nixpkgs ? rev then inputs.nixpkgs.shortRev else "dirty";
  selfRev = if inputs.self ? rev then inputs.self.shortRev else "dirty";
in
{

  options.${namespace}.hosts.live-usb = with types; {
    enable = mkBoolOpt false "Whether or not to enable the live-usb base config.";
  };
 # For reference, see //blog.thomasheartman.com/posts/building-a-custom-nixos-installer
  # but obviously flakified and broken apart.
  imports = [
    # base profiles
    "${modulesPath}/profiles/base.nix"
    "${modulesPath}/profiles/all-hardware.nix"

    # Let's get it booted in here
    "${modulesPath}/installer/cd-dvd/iso-image.nix"

    # Provide an initial copy of the NixOS channel so that the user
    # doesn't need to run "nix-channel --update" first.
    "${modulesPath}/installer/cd-dvd/channel.nix"
  ];

  config = mkIf cfg.enable {

    # Run through tor because finger printing or something? Supposed to be
    # relatively amnesiac.
    services.tor = {
      enable = true;
      client = {
        enable = true;
        dns.enable = true;
        transparentProxy.enable = true;
      };
    };

    users.mutableUsers = false;
    users.users.root.initialPassword = "root";
    programs.zsh.enable = true;

    # ISO naming.
    isoImage.isoName = "${hostname}-${nixRev}-${selfRev}.iso";

    # EFI + USB bootable
    isoImage.makeEfiBootable = true;
    isoImage.makeUsbBootable = true;

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

    # An installation media cannot tolerate a host config defined file
    # system layout on a fresh machine, before it has been formatted.
    swapDevices = mkImageMediaOverride [ ];
    fileSystems = mkImageMediaOverride config.lib.isoFileSystems;

    ${namespace} = {
    };
    
  };

}
