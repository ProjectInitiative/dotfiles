{
  config,
  lib,
  pkgs,
  ...
}:
{

  fileSystems."/boot" = {
    options = [
      "uid=0"
      "gid=0"
      "umask=0077"
      "fmask=0077"
      "dmask=0077"
    ];
  };

  # use systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Disable the GRUB 2 boot loader.
  boot.loader.grub = {
    enable = false;
    efiSupport = true;
    enableCryptodisk = true;
    device = "nodev";
  };
  #boot.loader.grub.enable = true;
  #boot.loader.grub.efiSupport = true;
  #boot.loader.grub.efiInstallAsRemovable = true;
  #boot.loader.efi.efiSysMountPoint = "/boot/efi";
  # Define on which hard drive you want to install Grub.
  #boot.loader.grub.device = "nodev"; # or "nodev" for efi only

  # luks
  boot.initrd.luks.devices = {
    cryptroot = {
      device = "/dev/disk/by-uuid/da93a286-8025-4de7-80b0-0aeecb71944f";
      preLVM = true;
    };
  };

}
