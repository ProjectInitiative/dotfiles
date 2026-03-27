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
  cfg = config.${namespace}.hardware.amdgpu-plugin;
in
{
  options.${namespace}.hardware.amdgpu-plugin = with types; {
    enable = mkBoolOpt false "Whether or not to enable AMD GPU Device Plugin for Kubernetes.";
  };

  config = mkIf cfg.enable {
    # This module could eventually deploy the AMD GPU Device Plugin to Kubernetes
    # For now, it just ensures the host is ready for it.
    # The actual driver config is currently in modules/nixos/hardware/amdgpu/default.nix
    # or systems/x86_64-linux/astrolabe/default.nix

    # Ensure the 'video' and 'render' groups exist (NixOS does this usually)
    # But we might want to ensure the Kubelet or runtime can access them.
  };
}
