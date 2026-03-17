{
  options,
  config,
  lib,
  pkgs,
  namespace,
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
    projectinitiative = {
      hosts.masthead.enable = true;
      hosts.masthead.role = "primary";
    };
  };
}
