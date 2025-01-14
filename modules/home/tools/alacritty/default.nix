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
  cfg = config.${namespace}.tools.alacritty;
  is-linux = pkgs.stdenv.isLinux;
  is-darwin = pkgs.stdenv.isDarwin;
in
{
  options.${namespace}.tools.alacritty = with types; {
    enable = mkBoolOpt false "Whether or not to enable common alacritty terminal emulator.";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        alacritty
      ];
    };
  };
}
