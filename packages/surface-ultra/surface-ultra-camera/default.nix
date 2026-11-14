# surface-ultra-camera — MediaTek MT8991 camera ISP driver (out-of-tree modules)
#
# From ikegam/surface-ultra-camera: makes the Surface Laptop Ultra's front
# camera (OmniVision OV02C10, 1920x1080@30 via libcamera software ISP) and IR
# camera (ST VD55G1, 592x600@30) work as libcamera cameras through PipeWire.
# Tested on kernel 7.3, libcamera 0.7.2, PipeWire 1.6 (arm64).
#
# FIRMWARE: requires nvCCU.img for the CCU (camera control unit) — extract
# from the machine's Windows partition with
# vendor/surface-ultra/surface-ultra-camera/firmware/extract-from-windows.sh
# and place at /lib/firmware/nvidia/n1x/nvCCU.img (wired below via
# hardware.firmware when `withFirmware` is given the file).
#
# Runtime: PipeWire needs LIBCAMERA_SOFTISP_MODE=cpu (the GPU software ISP
# does not work on NVIDIA's EGL); wired in the NixOS module.
# Commit-pinned: e95a23202f3a1c260f4e61476d0b0d464ebfba56 (2026-11-10).
{
  lib,
  pkgs,
  stdenv,
  kernel ? pkgs.linuxPackages_latest.kernel,
  kernelModuleMakeFlags ? [ ],
  # optional store path to nvCCU.img (accepted name: cameraFirmware/withFirmware)
  withFirmware ? null,
  cameraFirmware ? withFirmware,
}:

stdenv.mkDerivation {
  pname = "surface-ultra-camera";
  version = "unstable-2026-11-10";

  src = ../../../vendor/surface-ultra/surface-ultra-camera;

  sourceRoot = "source/kernel";

  prePatch = ''
    substituteInPlace Makefile \
      --replace-fail "KERNELRELEASE ?=" "KERNELRELEASE ="
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

  postInstall =
    lib.optionalString (cameraFirmware != null) ''
      mkdir -p $out/lib/firmware/nvidia/n1x
      cp ${cameraFirmware} $out/lib/firmware/nvidia/n1x/nvCCU.img
    ''
    + ''
      # libcamera pipeline config + IPA tuning file (from the repo's libcamera/
      # dir) — the NixOS module also symlinks these via environment.etc when
      # not installed here; keeping them in the package closure makes the
      # package self-contained.
      mkdir -p $out/share/libcamera
      cp -r $src/libcamera/* $out/share/libcamera/ 2>/dev/null || true
    '';

  meta = with lib; {
    description = "Kernel modules for the Surface Laptop Ultra (N1X) front (OV02C10) and IR (VD55G1) cameras via the MT8991 ISP";
    longDescription = ''
      Reverse-engineered driver; programs camera hardware registers directly.
      libcamera cameras "Surface Front Camera" / "Surface IR Camera" through
      PipeWire. Not both cameras at once. Not affiliated with Microsoft,
      NVIDIA or MediaTek — use at your own risk.
    '';
    license = licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
