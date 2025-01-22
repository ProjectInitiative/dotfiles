{
  lib,
  pkgs,
  inputs,
  namespace,
  config,
  options,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
{

  projectinitiative = {
    system = {
      base-vm = enabled;
    };
  };


  # # Use the boot drive for grub
  # boot.loader.grub.enable = lib.mkDefault true;
  # boot.loader.grub.devices = [ "nodev" ];


  # boot.kernelModules = [
  #   "bcachefs"
  #   "loop"
  # ];

  # # Create the loop devices and mount points in the live environment
  # boot.initrd.extraUtilsCommands = ''
  #   copy_bin_and_libs ${pkgs.coreutils}/bin/dd
  #   copy_bin_and_libs ${pkgs.util-linux}/bin/losetup
  # '';

  # boot.initrd.postDeviceCommands = ''
  #   # Create empty files for loop devices
  #   dd if=/dev/zero of=/tmp/disk1.img bs=1M count=1024
  #   dd if=/dev/zero of=/tmp/disk2.img bs=1M count=2048
  #   dd if=/dev/zero of=/tmp/disk3.img bs=1M count=3072
  #   dd if=/dev/zero of=/tmp/disk4.img bs=1M count=4096

  #   # Set up loop devices
  #   losetup /dev/loop0 /tmp/disk1.img
  #   losetup /dev/loop1 /tmp/disk2.img
  #   losetup /dev/loop2 /tmp/disk3.img
  #   losetup /dev/loop3 /tmp/disk4.img

  #   # Create bcachefs filesystem
  #   ${pkgs.bcachefs-tools}/bin/bcachefs format \
  #     --foreground_target=/dev/loop0 \
  #     --background_target=/dev/loop1 \
  #     --background_target=/dev/loop2 \
  #     --background_target=/dev/loop3 \
  #     --cache_device=/dev/sdb \
  #     /mnt/bcachefs
  # '';

  # fileSystems."/mnt/bcachefs" = {
  #   device = "/dev/loop0";
  #   fsType = "bcachefs";
  #   options = [ "defaults" ];
  # };

  # environment.systemPackages = with pkgs; [
  #   bcachefs-tools
  #   util-linux # for losetup
  # ];

  # # Make sure the initrd includes the necessary tools
  # boot.initrd.availableKernelModules = [
  #   "loop"
  #   "bcachefs"
  # ];
}
