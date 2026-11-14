# n1x-carveout — GPU carveout memmap module for the Surface Laptop Ultra
#
# `n1x_carveout_memmap` calls memremap_pages(MEMORY_DEVICE_PRIVATE) over the
# GPU carveout ranges that the Surface firmware HIDES from the EFI memory map
# (confirmed with efi=debug: the map jumps 0x1fcffffff -> 0x300000000). Without
# struct pages, the nvidia-open driver's vmap() path WARNs and the machine
# hard-resets when nvidia-drm creates its device. With it loaded (BEFORE
# nvidia), stock nvidia-open 615.78.08+ works: 0 WARNINGs, eDP connected,
# OpenGL 4.6 / Vulkan 1.4 on the 6144-core Blackwell GPU.
#
# Upstream write-up: https://gist.github.com/teo-casares/8b64949638e1952602a7f435bb34d5b8
# (Chapter 3). CAVEAT: ranges are hard-coded for EXPOSED_DISP_FRM = 4 GiB.
# Tracking: https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1521
{
  lib,
  pkgs,
  stdenv,
  kernel ? pkgs.linuxPackages_latest.kernel,
  kernelModuleMakeFlags ? [ ],
}:

stdenv.mkDerivation {
  pname = "n1x-carveout-memmap";
  version = "1.0";

  src = ../../../vendor/surface-ultra/gist-teo-casares;

  # Only the module sources; keep the derivation honest about what it builds.
  dontUnpack = true;
  preBuild = ''
    mkdir -p source
    cp $src/n1x_carveout_memmap.c source/
    cp $src/n1x_carveout_memmap.Makefile source/Makefile
    cd source
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags =
    kernelModuleMakeFlags
    ++ [
      "KERNELRELEASE=${kernel.modDirVersion}"
      "KERNEL_DIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "INSTALL_MOD_PATH=$(out)"
    ];

  # The Makefile in the gist is a minimal kbuild shim; ensure obj-m wiring.
  postPatch = ''
    if ! grep -q obj-m Makefile 2>/dev/null; then
      printf 'obj-m := n1x_carveout_memmap.o\n' >> Makefile
    fi
  '';

  installTargets = [ "modules_install" ];

  meta = with lib; {
    description = "Creates struct pages (memremap MEMORY_DEVICE_PRIVATE) for the N1X GPU carveout ranges hidden from the EFI memory map";
    longDescription = ''
      Load BEFORE nvidia (softdep nvidia pre: n1x_carveout_memmap, wired by the
      surface-laptop-ultra NixOS module). Ranges 0x200000000-0x2ffffffff and
      0xa1600000-0xb7ffffff; assumes EXPOSED_DISP_FRM = 4 GiB.
    '';
    license = licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
