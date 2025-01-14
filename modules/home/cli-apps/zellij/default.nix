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
  cfg = config.${namespace}.cli-apps.zellij;
  is-linux = pkgs.stdenv.isLinux;
  is-darwin = pkgs.stdenv.isDarwin;
in
{
  options.${namespace}.cli-apps.zellij = with types; {
    enable = mkBoolOpt false "Whether or not to enable common zellij terminal multiplexer.";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        zellij
      ];
    };
  };
}
