# /home/kylepzak/dotfiles/overlays/uboot/default.nix
{ inputs, ... }:
final: prev:
let
  # Create a dedicated unstable package set to draw from.
  # We only pass `system` to avoid configuration conflicts.
  unstablePkgs = import inputs.unstable {
    system = prev.stdenv.hostPlatform.system;
  };
in
{
  # --- U-Boot Dependencies ---
  # These are required by the U-Boot builds in the nixos-on-arm overlay.
  # We must pull them from unstable to match the U-Boot source.
  inherit (unstablePkgs)
    armTrustedFirmwareRK3588
    buildUBoot
    rkbin
    ubootTools;

  # --- U-Boot Packages ---
  # These are the actual board-specific U-Boot packages defined in the
  # nixos-on-arm overlay. By inheriting them from unstablePkgs, we are
  # using the versions that have that overlay applied.
  inherit (unstablePkgs)
    uboot-rk3582-generic
    ubootRock5ModelA
    ubootOrangePi5Ultra;
}