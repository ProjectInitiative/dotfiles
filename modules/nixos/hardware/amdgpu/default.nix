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
        libvdpau-va-gl
      ];
    };

    boot.initrd.kernelModules = [ "amdgpu" ];

    # We apply boot parameter amdgpu.gttsize=-1 if requested or by default for some
    boot.kernelParams = [ "amdgpu.gttsize=-1" ];
  };
}
