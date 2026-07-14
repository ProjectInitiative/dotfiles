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
  cfg = config.${namespace}.cli-apps.herdr;
in
{
  options.${namespace}.cli-apps.herdr = with types; {
    enable = mkBoolOpt false "Whether to enable herdr terminal multiplexer configuration.";
  };

  config = mkIf cfg.enable {

    home.packages = with pkgs; [
      herdr
    ];

  };
}
