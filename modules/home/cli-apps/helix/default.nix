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
  cfg = config.${namespace}.cli-apps.helix;
in
{
  options.${namespace}.cli-apps.helix = {
    enable = mkEnableOption "common helix editor and language servers."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        helix
        # language servers
        lsp-ai
        nil
        nixd
        python312Packages.python-lsp-server
        pyright
      ];

      sessionVariables = {
        EDITOR = "hx";
      };

    };
  };
}
