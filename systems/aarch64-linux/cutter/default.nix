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
    inputs.nixos-avf.nixosModules.avfInitial
    inputs.nixos-avf.nixosModules.avf
  ];

  # The AVF module handles:
  # - Kernel (linuxPackages_6_1 with patches — overridden below for cross)
  # - Bootloader (systemd-boot)
  # - FileSystems (/, /boot, /mnt/internal, /mnt/shared)
  # - Networking (systemd-networkd, avahi, ttyd)
  avf.defaultUser = "kylepzak";

  # Cross-compile the kernel on x86_64; use AVF's native kernel on aarch64.
  boot.kernelPackages = lib.mkOverride 40 (
    if builtins.getEnv "BUILD_ARM_NATIVE" == "true"
    then pkgs.linuxPackages_6_1
    else inputs.nixos-on-arm.linuxPackagesCross.x86_64-linux
  );

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
