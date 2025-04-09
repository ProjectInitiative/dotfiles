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
  cfg = config.${namespace}.cli-apps.zoxide;
in
{
  options.${namespace}.cli-apps.zoxide = {
    enable = mkEnableOption "zoxide cli."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        zoxide
        fzf
      ];

      shellAliases = {
        cd = "z";
      };
    };

    # Add shell-specific initialization
    programs.zsh.initExtra = mkIf config.programs.zsh.enable ''
      eval "$(zoxide init zsh)"
    '';

    programs.bash.initExtra = mkIf config.programs.bash.enable ''
      eval "$(zoxide init bash)"
    '';

    programs.fish.shellInit = mkIf config.programs.fish.enable ''
      zoxide init fish | source
    '';
  };
}
