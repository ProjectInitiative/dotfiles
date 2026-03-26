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

  # Use the specific latest kernel from the package set to preserve architecture
  baseKernel = pkgs.linuxPackages_latest.kernel;

  customKernel = baseKernel.overrideAttrs (oldAttrs: {
    # Apply patches and append DTS nodes directly
    postPatch = (oldAttrs.postPatch or "") + ''
            # Enable video nodes in Orange Pi 5 Ultra DTS
            cat >> arch/arm64/boot/dts/rockchip/rk3588-orangepi-5-ultra.dts <<EOF

      &vpu121 {
	status = "okay";
      };

      &vpu121_mmu {
	status = "okay";
      };

      &vdec0 {
	status = "okay";
      };

      &vdec0_mmu {
	status = "okay";
      };

      &vdec1 {
	status = "okay";
      };

      &vdec1_mmu {
	status = "okay";
      };

      &rkvenc0 {
	status = "okay";
      };

      &rkvenc0_mmu {
	status = "okay";
      };

      &rkvenc1 {
	status = "okay";
      };

      &rkvenc1_mmu {
	status = "okay";
      };

      &av1d {
	status = "okay";
      };

      &av1d_mmu {
	status = "okay";
      };
      EOF
    '';
  });

  # Apply regular patches and config
  customKernelPatched = customKernel.override {
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
      # Core dependencies
      ARCH_ROCKCHIP = yes;

      # MPP (Media Process Platform) drivers via patches
      VIDEO_ROCKCHIP_RKVENC = yes;

      # Mainline V4L2 Stateless Decoders
      VIDEO_ROCKCHIP_VDEC = yes;
      VIDEO_HANTRO = yes;
      VIDEO_HANTRO_ROCKCHIP = yes;

      # Media Framework for stateless decoders
      MEDIA_CONTROLLER_REQUEST_API = yes;
      VIDEO_MEM2MEM_DECODE_CONFIG = yes;

      # Builtin storage to satisfy initrd
      MMC_DW_ROCKCHIP = yes;
      MMC_SDHCI_ROCKCHIP = yes;
    };
    ignoreConfigErrors = true;
  };

  linuxPackages_rk3588 = pkgs.linuxPackagesFor customKernelPatched;

in
{
  options.${namespace}.system.rk3588-kernel = {
    enable = mkBoolOpt false "Custom RK3588 kernel with VEPU580 and HDMI-RX patches";
  };

  config = mkIf cfg.enable {
    boot.kernelPackages = mkForce linuxPackages_rk3588;
  };
}
