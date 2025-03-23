# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{
  config,
  lib,
  pkgs,
  modulesPath,
  nixos-hardware,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    binfmt = {
      emulatedSystems = [
        "aarch64-linux"
        "armv7l-linux"
        "armv6l-linux"
      ];
    };

    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "thunderbolt"
        "nvme"
      ];
      kernelModules = [ "dm-snapshot" ];
      luks.devices = {
        "nixos" = {
          device = "/dev/disk/by-uuid/fb793780-923f-4f0d-bb9b-cead23745d39";
          preLVM = true;
        };
      };
    };

    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];

    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 10; # Limit the number of configurations kept
        consoleMode = "auto";
        editor = false; # Disable the editor for security
      };

      efi.canTouchEfiVariables = true;

      grub.extraEntries = ''
        menuentry "NixOS" {
          loader /EFI/nixos/nixos-generation-X-filename.efi
        }
      '';

      timeout = 5; # Set a custom boot menu timeout (in seconds)
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/04f9ecc2-bb20-415f-aff5-c54285523fd3";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-partuuid/05399427-3ed0-4da7-bd08-740ddb6ce486";
      fsType = "vfat";
    };
    "/home/kylepzak" = {
      device = "/dev/mapper/data-home_kpzak";
      fsType = "ext4";
    };
    "/extpart" = {
      device = "/dev/mapper/data-extpart";
      fsType = "ext4";
    };
    "/backups" = {
      device = "/dev/mapper/data-backups";
      fsType = "ext4";
    };
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/b2530dee-4381-4a0f-a063-4871e2203999"; }
  ];

  networking = {
    useDHCP = lib.mkDefault true;
    # interfaces = {
    #   docker0.useDHCP = lib.mkDefault true;
    #   enp0s31f6.useDHCP = lib.mkDefault true;
    #   lxcbr0.useDHCP = lib.mkDefault true;
    #   mgmnt.useDHCP = lib.mkDefault true;
    #   tailscale0.useDHCP = lib.mkDefault true;
    #   vetha955db9.useDHCP = lib.mkDefault true;
    #   virbr0.useDHCP = lib.mkDefault true;
    #   wlp0s20f3.useDHCP = lib.mkDefault true;
    # };
  };

  # nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware = {
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
