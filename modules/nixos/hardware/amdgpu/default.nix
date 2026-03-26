{
  options,
  config,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hardware.amdgpu;
in
{
  options.${namespace}.hardware.amdgpu = with types; {
    enable = mkBoolOpt false "Whether or not to enable AMD GPU support.";
  };

  config = mkIf cfg.enable {
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        rocmPackages.clr
        rocmPackages.clr.icd
        # VA-API
        # We don't have libvdpau-va-gl but we can use libva, libvdpau, libva-utils
        # Or standard amdgpu packages
      ];
    };

    boot.initrd.kernelModules = [ "amdgpu" ];

    # We apply boot parameter amdgpu.gttsize=-1 in the host or system level
  };
}
