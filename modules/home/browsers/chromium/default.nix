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
  cfg = config.${namespace}.browsers.chromium;
  isGraphical = config.${namespace}.isGraphical;
in
{
  options.${namespace}.browsers.chromium = with types; {
    enable = mkBoolOpt false "Whether or not to enable chromium browser";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        chromium
      ];

    };
  };
}
