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
  cfg = config.${namespace}.browsers.chrome;
in
{
  options.${namespace}.browsers.chrome = with types; {
    enable = mkBoolOpt false "Whether or not to enable chrome browser";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        google-chrome
      ];

    };
  };
}
