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
  cfg = config.${namespace}.browsers.librewolf;
  isGraphical = config.${namespace}.isGraphical;
in
{
  options.${namespace}.browsers.librewolf = with types; {
    enable = mkBoolOpt false "Whether or not to enable librewolf browser";
  };

  config = mkIf (cfg.enable && isGraphical) {

    home = {
      packages = with pkgs; [
        librewolf
      ];

    };
  };
}
