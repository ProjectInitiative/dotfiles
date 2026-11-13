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
  cfg = config.${namespace}.browsers.tor;
  # null-guard for standalone-HM (container) contexts
  isGraphical = if osConfig != null then osConfig.${namespace}.isGraphical else false;
in
{
  options.${namespace}.browsers.tor = with types; {
    enable = mkBoolOpt false "Whether or not to enable tor browser";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        tor
        (mkIf isGraphical tor-browser)
      ];

    };
  };
}
