{
  options,
  config,
  pkgs,
  lib,
  # namespace, # No longer needed for helpers
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.gui.display-server.wayland;
in
{
  options.${namespace}.gui.display-server.wayland = {
    enable = mkEnableOption "wayland display server"; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {

    # Enable the Wayland windowing system.
    # services.wayland.enable = true;

  };

}
