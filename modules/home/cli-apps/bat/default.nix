{
  options,
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.cli-apps.bat;
in
{
  options.${namespace}.cli-apps.bat = {
    enable = mkEnableOption "bat cli."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        bat
      ];

      shellAliases = {
        cat = "bat";
      };
    };
  };
}
