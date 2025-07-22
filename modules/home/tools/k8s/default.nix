{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.tools.k8s;
in
{
  options.${namespace}.tools.k8s = with types; {
    enable = mkBoolOpt false "Whether or not to enable common Kubernetes utilities.";
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
        argocd
        cmctl
        istioctl
        cilium-cli
        hubble
      ];

      shellAliases = {
        k = "kubecolor";
        kubectl = "kubecolor";
        kx = "kubectx";
        kn = "kubens";
        delete-unbound-pv = "kubectl get pv -o json | jq -r '.items[] | select(.status.phase == \"Released\") | .metadata.name' | xargs -r kubectl delete pv";
        # kx = "kubectl ctx";
        # kn = "kubectl ns";
        # ks = "kubeseal";
      };
    };

  };
}
