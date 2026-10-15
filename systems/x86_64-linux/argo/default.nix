# argo — kubevirt VM (argo namespace on the mc cluster).
# Argo CD control plane + dev node. Disk layout comes from the shared
# hosts/argo module: 32Gi root (disposable) + 1Ti JuiceFS data disk
# (/data with /nix bind — survives root rebuilds and re-imports).
# The hosts/argo module is auto-loaded by snowfall; just flip the flag.
{ namespace, ... }:
{
  config.${namespace}.hosts.argo.enable = true;
}
