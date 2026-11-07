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
in
{
  options.${namespace}.hosts.masthead.stormjib = with types; {
    enable = mkBoolOpt false "Whether or not to enable the stormjib config.";
  };

  config = mkIf cfg.enable {
    ${namespace}.hosts.masthead = {
      # Cutover switch: stormjib replaces the OpenWrt router (2026-11-07).
      # Running solo as backup role is fine — a lone VRRP node with no peer
      # becomes MASTER and claims the VIPs after ~3s.
      enable = true;
      routerRole = "backup";
    };
  };
}
