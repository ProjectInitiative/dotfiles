{
  options,
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.tools.k8s;
in
{
  options.${namespace}.tools.k8s = {
    enable = mkEnableOption "common Kubernetes utilities."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [
        helmfile
        k9s
        kubecolor
        kubectl
        kubectx
        # kubeseal
        # krew
        kubernetes-helm
        kustomize
        kustomize-sops
        cilium-cli
        hubble
      ];

      shellAliases = {
        k = "kubecolor";
        kubectl = "kubecolor";
        kc = "kubectx";
        kn = "kubens";
        # kx = "kubectl ctx";
        # kn = "kubectl ns";
        # ks = "kubeseal";
      };
    };

  };
}
