# n1x-sdw-pads — MT8901 SoundWire pad drive strength fix (out-of-tree module)
#
# SoundWire link-0 pads (GPIO66/67) default to 2 mA drive strength, but the
# ACPI PinFunction vendor data ({0x04,0x08} on \_SB.CNT0) asks for 8 mA and
# mtk-sdw ignores it. At 2 mA the SoundWire bus never syncs (bus clash /
# parity storms, "no card from this controller") and no codec attaches.
# This module sets the pad drive through the pinctrl core (paris only
# implements per-group pinconf; each pin is a group) and must load BEFORE
# soundwire_mtk (softdep wired by the surface-laptop-ultra NixOS module).
#
# Upstream candidate: pinctrl/soundwire handling of the ACPI PinFunction data
# (Omarchy kernel 1030-n1x-audio.patch territory).
{
  lib,
  pkgs,
  stdenv,
  kernel ? pkgs.linuxPackages_latest.kernel,
  kernelModuleMakeFlags ? [ ],
}:

stdenv.mkDerivation {
  pname = "n1x-sdw-pads";
  version = "1.0";

  src = ../../../vendor/surface-ultra/gist-teo-casares;

  dontUnpack = true;
  preBuild = ''
    mkdir -p source
    cp $src/sdw_pad_drive.c source/sdw_pad_drive.c
    cd source
    printf 'obj-m := sdw_pad_drive.o\n' > Makefile
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags =
    kernelModuleMakeFlags
    ++ [
      "KERNELRELEASE=${kernel.modDirVersion}"
      "KERNEL_DIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "INSTALL_MOD_PATH=$(out)"
    ];

  installTargets = [ "modules_install" ];

  # Module options: groups=GPIO66,GPIO67 ma=8 (set via the NixOS module's
  # extraModprobeConfig, matching the vendored n1x-audio-sdw-pads.conf).

  meta = with lib; {
    description = "Sets MT8901 SoundWire link-0 pad (GPIO66/67) drive strength to 8 mA so the RT1320/RT721 codecs attach";
    license = licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
