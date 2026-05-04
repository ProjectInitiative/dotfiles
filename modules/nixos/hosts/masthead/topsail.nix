# Topsail (Primary): Agile sail for fair-weather speed (primary performance).

{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.masthead.topsail;
in
{
  options.${namespace}.hosts.masthead.topsail = with types; {
    enable = mkBoolOpt false "Whether or not to enable the topsail config.";
  };

  config = mkIf cfg.enable {
    ${namespace}.hosts.masthead = {
      enable = true;
      routerRole = "primary";
    };
  };
}
