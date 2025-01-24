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
  cfg = config.${namespace}.suites.development;
in
{
  options.${namespace}.suites.development = with types; {
    enable = mkBoolOpt false "Whether or not to enable common development configuration.";
  };

  config = mkIf cfg.enable {

    # Enable zsh system-wide
    programs.zsh.enable = true;

    ${namespace} = {
      networking = {
        tailscale = enabled;
      };

      virtualization = {
        podman = enabled;
        docker = enabled;
      };

      system = {
        locale = enabled;
        fonts = enabled;
      };

    };
  };
}
