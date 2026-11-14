# surface-ultra — aggregate package for all Surface Laptop Ultra (N1X) pieces
#
# Convenience attr pulling the kernel modules, daemon, and tools together.
# NOTE: the out-of-tree modules here build against `kernel` (default: latest);
# the NixOS module builds its own copies against the PATCHED kernel via
# callPackage — those are what actually get installed on the host. This
# aggregate exists for `nix flake check` / ad-hoc builds.
{
  lib,
  pkgs,
  symlinkJoin,

  kernel ? pkgs.linuxPackages_latest.kernel,
  withFirmware ? null,
}:

let
  carveout = pkgs.callPackage ./n1x-carveout { inherit kernel; };
  sdwPads = pkgs.callPackage ./n1x-sdw-pads { inherit kernel; };
  camera = pkgs.callPackage ./surface-ultra-camera {
    inherit kernel withFirmware;
  };
  ssamHelper = pkgs.callPackage ./surface-ultra-ssam-helper { inherit kernel; };
  thermald = pkgs.callPackage ./n1x-thermald { };
  tools = pkgs.callPackage ./surface-ultra-tools { };
in
symlinkJoin {
  name = "surface-ultra-${kernel.modDirVersion}";

  paths = [
    carveout
    sdwPads
    camera
    ssamHelper
    thermald
    tools
  ];

  meta = with lib; {
    description = "All out-of-tree modules, daemons and tools for the Microsoft Surface Laptop Ultra (NVIDIA RTX Spark N1X, aarch64)";
    platforms = [ "aarch64-linux" ];
  };
}
