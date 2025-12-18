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
    inputs.nixos-avf.nixosModules.avf
  ];

  # The AVF module handles:
  # - Kernel (linuxPackages_6_1 with patches)
  # - Bootloader (systemd-boot)
  # - FileSystems (/, /boot, /mnt/internal, /mnt/shared)
  # - Networking (systemd-networkd, avahi, ttyd)
  avf.defaultUser = "kylepzak";

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
}