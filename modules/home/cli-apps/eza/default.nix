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
  cfg = config.${namespace}.cli-apps.eza;
in
{
  options.${namespace}.cli-apps.eza = {
    enable = mkEnableOption "eza cli."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        eza
      ];

      shellAliases = {
        ls = "eza -alh";
        # ll = "eza -al";
      };
    };
  };
}
