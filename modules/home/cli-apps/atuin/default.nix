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
  cfg = config.${namespace}.cli-apps.atuin;
in
{
  options.${namespace}.cli-apps.atuin = with types; {
    enable = mkBoolOpt false "Whether or not to enable atuin cli.";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        atuin
      ];
    };

    # Enable blesh if bash is enabled
    # https://github.com/akinomyoga/ble.sh/wiki/Manual-A1-Installation#user-content-nixpkgs
    # programs.blesh.enable = mkIf config.programs.bash.enable true;

    # Add shell-specific initialization
    programs.zsh.initExtra = mkIf config.programs.zsh.enable ''
      eval "$(${pkgs.atuin} init zsh)"
    '';

    programs.bash.initExtra = mkIf config.programs.bash.enable ''
      eval "$(${pkgs.zoxide} init bash)"
    '';

    programs.fish.shellInit = mkIf config.programs.fish.enable ''
      ${pkgs.zoxide} init fish | source
    '';
  };
}
