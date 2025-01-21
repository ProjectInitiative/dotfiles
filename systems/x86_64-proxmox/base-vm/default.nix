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
    system = {
      base-vm = enabled;
    };
  };
}
