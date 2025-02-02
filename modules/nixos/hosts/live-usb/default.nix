# yoinked from https://github.com/dmadisetti/.dots/blob/template/nix/machines/momento.nix
{ lib, inputs, config, namespace, modulesPath, pkgs, options, ... }:
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

  # imports = [
  #   # base profiles
  #   "${modulesPath}/profiles/base.nix"
  #   "${modulesPath}/profiles/all-hardware.nix"

  #   # Let's get it booted in here
  #   "${modulesPath}/installer/cd-dvd/iso-image.nix"

  #   # Provide an initial copy of the NixOS channel so that the user
  #   # doesn't need to run "nix-channel --update" first.
  #   "${modulesPath}/installer/cd-dvd/channel.nix"

  #   # Add compatible kernel 
  #   "${modulesPath}/installer/cd-dvd/installation-cd-minimal-new-kernel-no-zfs.nix"

  # ];

  # config = mkIf cfg.enable {

  #   # RUN THROUGH TOR BECAUSE FINGER PRINTING OR SOMETHING? SUPPOSED TO BE
  #   # RELATIVELY AMNESIAC.
  #   # SERVICES.TOR = {
  #   #   ENABLE = FALSE;
  #   #   CLIENT = {
  #   #     ENABLE = TRUE;
  #   #     DNS.ENABLE = TRUE;
  #   #     TRANSPARENTPROXY.ENABLE = TRUE;
  #   #   };
  #   # };

  #   # ENABLE NETWORKING
  #   # NETWORKING = MKFORCE {
  #   #   NETWORKMANAGER.ENABLE = TRUE;  # ENABLE NETWORKMANAGER
  #   #   USEDHCP = TRUE;               # ENABLE DHCP GLOBALLY
  #   # };

  #   PROGRAMS.ZSH.ENABLE = TRUE;
  #     # DISABLE PASSWORD AUTHENTICATION GLOBALLY
  #   USERS.MUTABLEUSERS = FALSE;
  #   # ENABLE AUTO-LOGIN FOR CONSOLE
  #   SERVICES.GETTY.AUTOLOGINUSER = MKFORCE "ROOT";

  #   # IF YOU'RE USING DISPLAY MANAGER (LIKE SDDM, GDM, ETC), CONFIGURE AUTO-LOGIN THERE TOO
  #   SERVICES.DISPLAYMANAGER.AUTOLOGIN = {
  #     ENABLE = TRUE;
  #     USER = "ROOT";
  #   };

  #   # ISO NAMING.
  #   ISOIMAGE.ISONAME = MKFORCE "NIXOS-${HOSTNAME}-${NIXREV}-${SELFREV}.ISO";

  #   # EFI + USB BOOTABLE
  #   ISOIMAGE.MAKEEFIBOOTABLE = TRUE;
  #   ISOIMAGE.MAKEUSBBOOTABLE = TRUE;

  #   BOOT.SUPPORTEDFILESYSTEMS = [ "BCACHEFS" ];
  #   BOOT.KERNELPACKAGES = LIB.MKOVERRIDE 0 PKGS.LINUXPACKAGES_LATEST;

  #   # OTHER CASES
  #   ISOIMAGE.APPENDTOMENULABEL = " LIVE";
  #   # ISOIMAGE.CONTENTS = [{
  #   #   SOURCE = "/PATH/TO/SOURCE/FILE";
  #   #   TARGET = "/PATH/IN/ISO";
  #   # }];
  #   # ISOFILESYSTEMS <- ADD LUKS (SEE ISSUE DMADISETTI/#34)
  #   # BOOT.LOADER = REC {
  #   #   GRUB2-THEME = {
  #   #     ENABLE = TRUE;
  #   #     ICON = "";
  #   #     THEME = "";
  #   #     SCREEN = "1080P";
  #   #     SPLASHIMAGE = ../../DOT/BACKGROUNDS/LIVE.PNG;
  #   #     FOOTER = TRUE;
  #   #   };
  #   # };
  #   # ISOIMAGE.GRUBTHEME = CONFIG.BOOT.LOADER.GRUB.THEME;
  #   ISOIMAGE.SPLASHIMAGE = CONFIG.BOOT.LOADER.GRUB.SPLASHIMAGE;
  #   ISOIMAGE.EFISPLASHIMAGE = CONFIG.BOOT.LOADER.GRUB.SPLASHIMAGE;

  #   # ADD MEMTEST86+ TO THE ISO.
  #   BOOT.LOADER.GRUB.MEMTEST86.ENABLE = TRUE;

  #   # AN INSTALLATION MEDIA CANNOT TOLERATE A HOST CONFIG DEFINED FILE
  #   # SYSTEM LAYOUT ON A FRESH MACHINE, BEFORE IT HAS BEEN FORMATTED.
  #   SWAPDEVICES = MKIMAGEMEDIAOVERRIDE [ ];
  #   FILESYSTEMS = MKIMAGEMEDIAOVERRIDE CONFIG.LIB.ISOFILESYSTEMS;

  #   ${NAMESPACE} = {
  #   };
    
  # };

}
