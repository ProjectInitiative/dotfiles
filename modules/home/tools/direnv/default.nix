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
  cfg = config.${namespace}.tools.direnv;
in
{
  options.${namespace}.tools.direnv = {
    enable = mkEnableOption "direnv."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {
    programs.direnv = {
      enable = true; # Standard boolean
      nix-direnv.enable = true; # Use standard boolean
    };
  };
}
