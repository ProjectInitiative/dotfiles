# Cross-compiled NVIDIA DGX Spark kernel (x86_64 → aarch64-linux).
#
# Mirrors the NVIDIA kernel construction from the nixos-dgx-spark flake
# (modules/dgx-spark.nix) but evaluates it against pkgsCross so every native
# build tool (gcc, make, ...) is a native x86_64 binary. Without this, the
# aarch64 kernel runs its whole build under QEMU binfmt emulation, which is
# far too slow for a multi-hour NVIDIA kernel + driver build.
#
# This is a temporary measure: once the DGX Sparks arrive and boot, build
# with BUILD_ARM_NATIVE=true and the nixos-dgx-spark module's self-hosted
# NVIDIA kernel is used instead (see modules/nixos/hosts/dgx-spark/default.nix).
#
# NOTE: keep the kernel derivation args in sync with the upstream module —
# the source rev/hash live in kernel-configs/nvidia-kernel-source.nix.
{
  inputs,
  lib,
  ...
}:
let
  dgx = inputs.nixos-dgx-spark;

  kernelSource = import "${dgx}/kernel-configs/nvidia-kernel-source.nix";
  linux617Overlay = import "${dgx}/overlays/linux-6.17.nix";

  # x86_64 pkgs with an aarch64 cross toolchain. buildPlatform stays x86_64 so
  # all nativeBuildInputs run natively; the kernel itself is compiled for
  # aarch64-linux. Same approach as nixos-on-arm's linuxPackagesCross.
  crossPkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    crossSystem = inputs.nixpkgs.lib.systems.examples.aarch64-multiplatform;
    config = {
      allowUnfree = true;
      allowUnsupportedSystem = true;
      cudaSupport = true;
      cudaCapabilities = [ "12.0" "12.1" ];
    };
    overlays = [ linux617Overlay ];
  };

  dgxKernelConfig = import (
    "${dgx}/kernel-configs/nvidia-dgx-spark-${kernelSource.nvidiaKernelVersion}.nix"
  ) { inherit lib; };

  nvidiaKernelPatches = [
    {
      name = "rust-gendwarfksyms-fix";
      patch = "${dgx}/patches/rust-gendwarfksyms-fix.patch";
    }
  ];

  # linux_6_17 is EOL upstream; the overlay repoints it at linux_latest and the
  # argsOverride below replaces the source/version/config with NVIDIA's.
  baseKernel = crossPkgs.linux_6_17;
in
crossPkgs.linuxPackagesFor (
  baseKernel.override {
    argsOverride = {
      src = kernelSource.mkNvidiaKernelSource crossPkgs;
      version = "${kernelSource.nvidiaKernelVersion}-nvidia";
      modDirVersion = kernelSource.nvidiaKernelVersion;
      kernelPatches = nvidiaKernelPatches;
    };

    enableCommonConfig = true;
    ignoreConfigErrors = true;

    structuredExtraConfig =
      dgxKernelConfig
      // (with lib.kernel; {
        SECURITY_APPARMOR_BOOTPARAM_VALUE = freeform "1";
        SECURITY_APPARMOR_RESTRICT_USERNS = lib.mkForce yes;

        USB_STORAGE = yes;
        USB_UAS = yes;
        OVERLAY_FS = yes;

        UEVENT_HELPER = no;

        UBUNTU_HOST = no;
      });
  }
)
