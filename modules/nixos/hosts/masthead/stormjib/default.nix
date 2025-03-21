# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).

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
  cfg = config.${namespace}.hosts.masthead.stormjib;
  sops = config.sops;
in
{
  options.${namespace}.hosts.masthead.stormjib = with types; {
    enable = mkBoolOpt false "Whether or not to enable the stormjib config.";
  };

  config = mkIf cfg.enable {

    projectinitiative = {
      hosts.masthead.enable = true;
    };

  };
}
