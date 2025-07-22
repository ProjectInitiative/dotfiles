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
  cfg = config.${namespace}.cli-apps.bat;
in
{
  options.${namespace}.cli-apps.bat = with types; {
    enable = mkBoolOpt false "Whether or not to enable bat cli.";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        bat
      ];

      shellAliases = {
        cat = "bat";
        batlog = "bat --paging=never -l log";
      };
    };

    programs.zsh.initContent = mkIf config.programs.zsh.enable ''
      batdiff() {
          git diff --name-only --relative --diff-filter=d -z | xargs --null bat --diff
      }
    '';

    programs.bash.initExtra = mkIf config.programs.bash.enable ''
      batdiff() {
          git diff --name-only --relative --diff-filter=d -z | xargs --null bat --diff
      }
    '';
  };
}
