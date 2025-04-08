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
  cfg = config.${namespace}.browsers.ladybird;
  isGraphical = osConfig.${namespace}.isGraphical or false;
in
{
  options.${namespace}.browsers.ladybird = with types; {
    enable = mkBoolOpt false "Whether or not to enable ladybird browser";
  };

  config = mkIf (cfg.enable && isGraphical) {

    home = {
      packages = with pkgs; [
        ladybird
      ];

    };
  };
}
