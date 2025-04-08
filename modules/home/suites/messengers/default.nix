{
  options,
  config,
  pkgs,
  lib,
  namespace,
  osConfig ? { },
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.suites.messengers;
  isGraphical = osConfig.${namespace}.isGraphical or false;
in
{
  options.${namespace}.suites.messengers = with types; {
    enable = mkBoolOpt false "Whether or not to enable messengers suite";
  };

  config = mkIf cfg.enable {

    home = {
      packages =
        with pkgs;
        mkIf isGraphical [
          element-desktop
          signal-desktop
          telegram-desktop
          thunderbird
        ];
    };

  };

}
