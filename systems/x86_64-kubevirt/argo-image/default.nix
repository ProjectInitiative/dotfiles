{
  lib,
  pkgs,
  inputs,
  namespace,
  config,
  options,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
{
  # Generic argo estate image (qcow2 for CDI import into the KubeVirt VM).
  # Named "argo-image" because snowfall keys systems by NAME — argo itself
  # lives in systems/x86_64-linux/argo for normal nixos-rebuild rebuilds.
  # Both thin files enable the SAME modules/nixos/hosts/argo module, so the
  # image and the live config cannot drift.
  projectinitiative.hosts.argo = enabled;
  networking.hostName = mkForce "argo";
}
