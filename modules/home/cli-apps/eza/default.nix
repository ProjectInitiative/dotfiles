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
  cfg = config.${namespace}.cli-apps.eza;
in
{
  options.${namespace}.cli-apps.eza = with types; {
    enable = mkBoolOpt false "Whether or not to enable eza cli.";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        eza
      ];

      shellAliases = {
        ls = "eza -alh";
        # ll = "eza -al";
      };
    };
  };
}
