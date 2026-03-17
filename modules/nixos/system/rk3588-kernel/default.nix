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
      # Append MPP nodes to Orange Pi 5 Ultra DTS
      cat >> arch/arm64/boot/dts/rockchip/rk3588-orangepi-5-ultra.dts <<EOF

&{/} {
	mpp_srv: mpp-srv {
		compatible = "rockchip,mpp-service";
		rockchip,taskqueue-count = <12>;
		rockchip,resetgroup-count = <1>;
		status = "okay";
	};

	rkvenc_ccu: rkvenc-ccu {
		compatible = "rockchip,rkv-encoder-v2-ccu";
		status = "okay";
	};
};

&rkvenc0 {
	status = "okay";
	rockchip,srv = <&mpp_srv>;
	rockchip,ccu = <&rkvenc_ccu>;
	rockchip,taskqueue-node = <7>;
	rockchip,resetgroup-node = <0>;
};

&rkvenc1 {
	status = "okay";
	rockchip,srv = <&mpp_srv>;
	rockchip,ccu = <&rkvenc_ccu>;
	rockchip,taskqueue-node = <7>;
	rockchip,resetgroup-node = <0>;
};

&vpu121 {
	status = "okay";
	rockchip,srv = <&mpp_srv>;
	rockchip,taskqueue-node = <1>;
};

&av1d {
	status = "okay";
	rockchip,srv = <&mpp_srv>;
	rockchip,taskqueue-node = <4>;
};

&vpu121_mmu {
	status = "okay";
};

&rkvenc0_mmu {
	status = "okay";
};

&rkvenc1_mmu {
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

      # Specific hardware drivers
      VIDEO_ROCKCHIP_RKVENC = module;
      VIDEO_ROCKCHIP_VDEC = module;
      VIDEO_HANTRO = module;
      VIDEO_HANTRO_ROCKCHIP = yes;

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
