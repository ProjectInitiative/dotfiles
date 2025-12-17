{
  config,
  pkgs,
  inputs,
  namespace,
  lib,
  modulesPath,
  ...
}:

with lib;
with lib.${namespace};

let
  # Assume namespace is "projectinitiative" as seen in flake.nix
  cfg = config.${namespace};
in
{
  imports = [
    # General QEMU guest profile for common virtual machine optimizations
    (modulesPath + "/profiles/qemu-guest.nix")
  ];


  # Bootloader and kernel modules for a VM
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
    "usbhid"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  # File systems based on lsblk output
  fileSystems."/" = {
    device = "/dev/vda2";
    fsType = "ext4"; # Assuming ext4, user can adjust if needed
  };

  fileSystems."/boot" = {
    device = "/dev/vda1";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ]; # No swap shown in lsblk output

  # Networking: Simple DHCP
  networking.useDHCP = lib.mkDefault true;


  projectinitiative = {
    
    settings = {
      stateVersion = "25.05";
    };

    system = {
      nix-config = enabled;
    };

    
    suites = {
        loft = {
          enable = true;
          enableClient = true;
          enableServer = true;
        };
      development = enabled;
    };
  };

  # Enable OpenSSH for remote access
  services.openssh.enable = true;

  # Minimal environment: no extra services or desktop environment by default
  # User can add custom packages later in their home-manager or global config.
}
