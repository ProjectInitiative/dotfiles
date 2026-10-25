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
  # Plain cross-compiled aarch64 kernel from nixpkgs (no Rockchip patches).
  # AVF applies its own 6.1 patches via boot.kernelPatches.
  crossKernel =
    inputs.nixpkgs.legacyPackages.x86_64-linux.pkgsCross.aarch64-multiplatform.linuxPackages_6_1;

  cfg = config.${namespace};
in
{
  imports = [
    inputs.nixos-avf.nixosModules.avfInitial
    inputs.nixos-avf.nixosModules.avf
  ];

  # The AVF module handles:
  # - Kernel (linuxPackages_6_1 with patches — cross-compiled below on x86_64)
  # - Bootloader (systemd-boot)
  # - FileSystems (/, /boot, /mnt/internal, /mnt/shared)
  # - Networking (systemd-networkd, avahi, ttyd)
  avf.defaultUser = "kylepzak";

  # Cross-compile the kernel on x86_64; use AVF's native kernel on aarch64.
  boot.kernelPackages = lib.mkOverride 40 (
    if builtins.getEnv "BUILD_ARM_NATIVE" == "true" then pkgs.linuxPackages_6_1 else crossKernel
  );

  # koiTerminal (unlike upstream GrapheneOS Terminal) only materializes the
  # "android" virtiofs share (from /storage/emulated); the "internal" share
  # ($APP_DATA_DIR/files) is dropped by ConfigJson.SharedPathJson. Without
  # nofail the guest drops to emergency mode on the failed /mnt/internal
  # mount. Matches outlawsanzhang/nixos-avf-koiTerminal.
  fileSystems."/mnt/internal".options = [ "nofail" ];
  fileSystems."/mnt/shared".options = [ "nofail" ];

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
