# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).

{ ... }:
{
  config = {
    projectinitiative = {
      hosts.masthead.stormjib.enable = true;
    };
  };
}
