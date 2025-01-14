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
  cfg = config.${namespace}.cli-apps.bat;
in
{
  options.${namespace}.cli-apps.bat = with types; {
    enable = mkBoolOpt false "Whether or not to enable bat cli.";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        bat
      ];

      shellAliases = {
        cat = "bat";     
      };
    };
  };
}
