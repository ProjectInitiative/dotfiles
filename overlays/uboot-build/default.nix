{ channels, inputs, ... }:

final: prev: {
  # Just use the version from the channels.nixpkgs that you've provided
  # We are defining a NEW package from scratch using the 'buildUBoot'
  # factory function, which is the proper way to do this.
  uboot-rk3582-generic = channels.nixpkgs-master.buildUBoot {
    pname = "uboot-rk3582-generic";
    # Use the version from the default U-Boot in nixpkgs, and add a suffix.
    version = "${prev.ubootOrangePi5.version}-rk3582-patched";

    # --- Critical Build Configuration ---
    # We use the generic RK3588 defconfig, which your patch modifies.
    defconfig = "generic-rk3588_defconfig";
    
    # Add our patches.
    extraPatches = [
      ./patches/0001-rockchip-Add-initial-RK3582-support.patch
      ./patches/0002-rockchip-rk3588-generic-Enable-support-for-RK3582.patch
    ];

    # --- Dependencies for RK3588/RK3582 Architecture ---
    # These are the same dependencies the other RK3588 boards need.
    BL31 = "${prev.armTrustedFirmwareRK3588}/bl31.elf";
    ROCKCHIP_TPL = prev.rkbin.TPL_RK3588;
    
    # --- Output Files ---
    # Tell the build what files to copy to the output directory.
    filesToInstall = [
      "u-boot.itb"
      "idbloader.img"
      "u-boot-rockchip.bin"
      # "u-boot-rockchip-spi.bin"
    ];
    
    # --- Metadata ---
    extraMeta = {
      description = "Patched U-Boot for generic RK3582/RK3588 boards";
      platforms = [ "aarch64-linux" ];
    };
  };
}

