# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).

{
  options,
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  modulesPath,
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.hosts.masthead.stormjib;
  sops = config.sops;
in
{
  options.${namespace}.hosts.masthead.stormjib = {
    enable = mkEnableOption "the stormjib config."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {

    projectinitiative = {
      hosts.masthead.enable = true;
    };

  };
}
