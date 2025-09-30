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
  cfg = config.${namespace}.cli-apps.ripgrep;
in
{
  options.${namespace}.cli-apps.ripgrep = with types; {
    enable = mkBoolOpt false "Whether or not to enable ripgrep cli.";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        ripgrep
      ];

      shellAliases = {
      };
    };
  };
}
