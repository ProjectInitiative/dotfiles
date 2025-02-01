{
  options,
  config,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.suites.messengers;
in
{
  options.${namespace}.suites.messengers = with types; {
    enable = mkBoolOpt false "Whether or not to enable messengers suite";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
          element-desktop
          signal-desktop
          telegram-desktop
          thunderbird
        ];
    };

  };

}
