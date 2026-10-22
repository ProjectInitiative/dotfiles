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
    hosts = {
      argo = enabled;
    };
  };
}
