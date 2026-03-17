{
  options,
  config,
  lib,
  pkgs,
  namespace,
  inputs,
  ...
}:

with lib;
with lib.${namespace};

let
  cfg = config.${namespace}.system.rk3588-kernel;

  # Use a kernel version close to what the patches were tested on (v6.19-rc8)
  # linuxPackages_latest is currently 6.18.x which should be close enough.
  baseKernel = pkgs.linux_latest;

  customKernel = baseKernel.override {
    kernelPatches = (baseKernel.kernelPatches or [ ]) ++ [
      {
        name = "rk3588-vepu580-encoder";
        patch = ./patches/0001-rockchip-rk3588-vepu580-encoder-support-v3.patch;
      }
      {
        name = "rk3588-hdmirx-edid-fix";
        patch = ./patches/0002-rockchip-rk3588-hdmirx-edid-fix-v1.patch;
      }
      {
        name = "rk3588-hdmirx-plugout-fix";
        patch = ./patches/0003-rockchip-rk3588-hdmirx-plugout-fix-v1.patch;
      }
    ];
    structuredExtraConfig = with lib.kernel; {
      VIDEO_ROCKCHIP_RKVENC = module;
      VIDEO_ROCKCHIP_VDEC = module;
      VIDEO_HANTRO = module;
      VIDEO_HANTRO_ROCKCHIP = yes;
    };
    ignoreConfigErrors = false;
  };

  linuxPackages_rk3588 = pkgs.linuxPackagesFor customKernel;

in
{
  options.${namespace}.system.rk3588-kernel = {
    enable = mkBoolOpt false "Custom RK3588 kernel with VEPU580 and HDMI-RX patches";
  };

  config = mkIf cfg.enable {
    boot.kernelPackages = mkForce linuxPackages_rk3588;

    # Add the DTS overlay for video hardware
    hardware.deviceTree.overlays = [
      {
        name = "rk3588-rkvenc-mpp";
        dtsFile = ./patches/rockchip-rk3588-rkvenc-mpp.dts;
      }
    ];
  };
}
