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
  cfg = config.${namespace}.gui.display-server.xorg;
in
{
  options.${namespace}.gui.display-server.xorg = with types; {
    enable = mkBoolOpt false "Whether or not to enable xorg display server";
  };

  config = mkIf cfg.enable {

    # Enable the xorg display-server.
    # services.xserver.enable = true;

  };

}
