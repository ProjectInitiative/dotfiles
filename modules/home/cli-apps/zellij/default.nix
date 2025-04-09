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
  cfg = config.${namespace}.cli-apps.zellij;
  is-linux = pkgs.stdenv.isLinux;
  is-darwin = pkgs.stdenv.isDarwin;
in
{
  options.${namespace}.cli-apps.zellij = {
    enable = mkEnableOption "common zellij terminal multiplexer."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        zellij
      ];
    };
  };
}
