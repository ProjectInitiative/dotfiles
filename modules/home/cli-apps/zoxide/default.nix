{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.cli-apps.zoxide;
in
{
  options.${namespace}.cli-apps.zoxide = with types; {
    enable = mkBoolOpt false "Whether or not to enable zoxide cli.";
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
      eval "$(${pkgs.zoxide} init zsh)"
    '';

    programs.bash.initExtra = mkIf config.programs.bash.enable ''
      eval "$(${pkgs.zoxide} init bash)"
    '';

    programs.fish.shellInit = mkIf config.programs.fish.enable ''
      ${pkgs.zoxide} init fish | source
    '';
  };
}
