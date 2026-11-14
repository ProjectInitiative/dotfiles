# surface-ultra-ssam-helper — SSAM UART clock + client modules (out-of-tree)
#
# From ikegam/surface-ultra-misc (ssam-helper/), commit-pinned 2026-11-12.
# Two NEW, self-contained out-of-tree modules; nothing in-tree is replaced:
#
#   n1x_ssam_uartclk — sets the real 52 MHz clock of the SAM EC UART
#     (NVDA0240) before stock surface_aggregator opens it, and corrects the
#     fractional divider that mtk8250_set_termios() gets wrong above 42.9 MHz
#     (32-bit overflow). This is the alternative to the kernel-patches 0001 /
#     0002 approach: with this module, the stock SSAM drivers work UNPATCHED.
#
#   n1x_ssam_clients — platform hub for MSHW0733 registering battery, AC, the
#     11 SSAM temperature sensors (hwmon surface_thermal, tempN = SAM instance
#     N) and fan speed. EC HID devices intentionally NOT registered (they
#     fight the I2C keyboard/touchpad).
#
# Load order: n1x_ssam_uartclk BEFORE surface_aggregator (softdep wired by
# the NixOS module).
#
# MUTUAL EXCLUSIVITY with kernel-patches 0001/0002/0003: if this package is
# enabled, disable kernel patches 0001 and 0002 (both fix the same UART
# clock) and 0003 (n1x_ssam_clients replaces the MSHW0733 registry entry).
# The NixOS module enforces an assertion.
{
  lib,
  pkgs,
  stdenv,
  kernel ? pkgs.linuxPackages_latest.kernel,
  kernelModuleMakeFlags ? [ ],
}:

stdenv.mkDerivation {
  pname = "surface-ultra-ssam-helper";
  version = "unstable-2026-11-12";

  src = ../../../vendor/surface-ultra/surface-ultra-misc/ssam-helper;

  prePatch = ''
    substituteInPlace Makefile --replace-fail "KVER ?= \$(shell uname -r)" "KVER = ${kernel.modDirVersion}"
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags =
    kernelModuleMakeFlags
    ++ [
      "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "INSTALL_MOD_PATH=$(out)"
    ];

  # The upstream Makefile has no modules_install; do it explicitly.
  installPhase = ''
    runHook preInstall
    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      M=$(pwd) INSTALL_MOD_PATH=$out modules_install
    runHook postInstall
  '';

  meta = with lib; {
    description = "SSAM helper modules for the Surface Laptop Ultra: 52 MHz SAM UART clock fix + MSHW0733 clients (battery, AC, thermal sensors, fan)";
    license = licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
