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
  cfg = config.${namespace}.suites.terminal-env;
in
{
  options.${namespace}.suites.terminal-env = with types; {
    enable = mkBoolOpt false "Whether or not to enable common terminal-env configuration.";
  };

  config = mkIf cfg.enable {
    ${namespace} = {
      cli-apps = {
        helix = enabled;
        atuin = enabled;
        zellij = enabled;
        # QOL cli
        bat = enabled;
        eza = enabled;
      };

      tools = {
        alacritty = enabled;
      };
    };
  };
}
