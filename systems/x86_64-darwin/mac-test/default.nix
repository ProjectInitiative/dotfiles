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

  projectinitiative = {
    # hosts = {
    #   base-vm = enabled;
    # };
  };

  system.stateVersion = "24.11";
}
