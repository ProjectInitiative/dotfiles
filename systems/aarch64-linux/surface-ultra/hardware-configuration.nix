# PLACEHOLDER hardware configuration for surface-ultra.
#
# TODO(hardware): regenerate on the real machine with nixos-generate-config
# after install-media boot, then replace this file. The UUIDs below are
# DUMMIES — they will not match any real disk. Disk: Micron 4600 NVMe.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    initrd = {
      # NVMe + xhci needed to find root; USB keyboard may need xhci_hid modules.
      availableKernelModules = [
        "xhci_pci"
        "nvme"
        "usb_storage"
        "sd_mod"
        "usbhid"
      ];
      kernelModules = [ ];
    };

    kernelModules = [ ];

    loader = {
      # GRUB (NOT systemd-boot, NOT Limine) — enforced/overridden by the SLU
      # hardware module; kept here for documentation.
      grub.enable = true;
      efi.canTouchEfiVariables = false; # Project Mu NVRAM writes unreliable
    };
  };

  fileSystems = {
    # TODO(hardware): real UUIDs from nixos-generate-config.
    "/" = {
      device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000001";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/0000-0001";
      fsType = "vfat";
    };
  };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface.
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
