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
  cfg = config.${namespace}.gui.display-server.wayland;
in
{
  options.${namespace}.gui.display-server.wayland = with types; {
    enable = mkBoolOpt false "Whether or not to enable wayland display server";
  };

  config = mkIf cfg.enable {

    # Enable the Wayland windowing system.
    # services.wayland.enable = true;

  };

}
