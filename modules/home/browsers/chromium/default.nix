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
  cfg = config.${namespace}.browsers.chromium;
  isGraphical = osConfig.${namespace}.isGraphical;
in
{
  options.${namespace}.browsers.chromium = with types; {
    enable = mkBoolOpt false "Whether or not to enable chromium browser";
  };

  config = mkIf (cfg.enable && isGraphical) {

    home = {
      packages = with pkgs; [
        chromium
      ];

    };
  };
}
