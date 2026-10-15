# argo — kubevirt VM (argo namespace on the mc cluster).
# Argo CD control plane + dev node. Disk layout comes from the shared
# hosts/argo module: 32Gi root (disposable) + 1Ti JuiceFS data disk
# (/data with /nix bind — survives root rebuilds and re-imports).
{
  config,
  lib,
  namespace,
  ...
}:
{
  imports = [ ../../../modules/nixos/hosts/argo ];

  config = {
    ${namespace}.hosts.argo.enable = true;

    # live-migration friendly: no host-pinned state, DHCP on the pod network
    networking.hostName = "argo";
  };
}
