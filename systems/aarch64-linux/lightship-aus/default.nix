# /etc/nixos/hosts/lighthouse-east.nix
{ config, pkgs, namespace, modulesPath, ... }:

let
  # Use /dev/sda as the root disk for Hetzner cloud instances
  rootDiskDevicePath = "/dev/sda";
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];


  # Enable and configure the common hetzner module for this host
  ${namespace}.hosts.lighthouse = {
    enable = true;
    role = "server"; # This is the master node
    k8sServerAddr = "https://100.94.107.39:6443";
  };

  # Disko configuration for a single disk with LVM
  disko.devices = {
    disk.rootSystemDisk = {
      type = "disk";
      device = rootDiskDevicePath;
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02"; # BIOS boot partition
          };
          # EFI System Partition (ESP) for booting
          ESP = {
            name = "ESP";
            type = "EF00";
            size = "512M";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          # Partition for LVM Physical Volume
          lvm_pv_root = {
            name = "lvm_pv";
            size = "100%";
            content = {
              type = "lvm_pv";
              vg = "vgSystem";
            };
          };
        };
      };
    };
    lvm_vg.vgSystem = {
      type = "lvm_vg";
      lvs = {
        lvRoot = {
          name = "root";
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  # GRUB Bootloader Configuration for EFI system
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev"; # Required for disko
  };
  boot.loader.efi.canTouchEfiVariables = false;
}
