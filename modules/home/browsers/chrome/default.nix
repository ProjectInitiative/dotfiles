{
  options,
  config,
  lib,
  pkgs,
  namespace,
  osConfig ? { },
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.browsers.chrome;
  isGraphical = osConfig.${namespace}.isGraphical or false;
in
{
  options.${namespace}.browsers.chrome = with types; {
    enable = mkBoolOpt false "Whether or not to enable chrome browser";
  };

  config = mkIf (cfg.enable && isGraphical) {

    home = {
      packages = with pkgs; [
        google-chrome
      ];

    };
  };
}
