# modules/nixos/hardware/amdgpu/default.nix
{ config, lib, pkgs, namespace, upstream ? pkgs, ... }:
with lib;
let
  cfg = config.${namespace}.hardware.amdgpu;
in
{
  options.${namespace}.hardware.amdgpu.enable = mkEnableOption "AMD GPU support";

  config = mkIf cfg.enable {
    hardware.graphics = {
      enable = true;
      # 'unstable' now comes from your host's specialArgs
      extraPackages = with upstream; [
        rocmPackages.clr
        rocmPackages.clr.icd
        libvdpau-va-gl
        libva-vdpau-driver
      ];
    };

    # Memory optimizations for the 128GB unified RAM
    boot.kernelParams = [
      "amdgpu.gttsize=102400"
      "ttm.pages_limit=26214400"
      "amdgpu.vis_vram_limit=102400"
      "amdgpu.svm_max_mapping_size=131072"  # 128GB in MB
      "amd_iommu=on"
      "iommu=pt"
    ];

    boot.initrd.kernelModules = [ "amdgpu" ];

    swapDevices = [];
    

    environment.variables = {
      HSA_OVERRIDE_GFX_VERSION = "11.5.1";
      HSA_ENABLE_SDMA = "0"; 
    };

    environment.systemPackages = with upstream; [
      rocmPackages.rocm-smi
      rocmPackages.rocminfo
    ];
  };
}