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
  cfg = config.${namespace}.cli-apps.nix;
in
{
  options.${namespace}.cli-apps.nix = with types; {
    enable = mkBoolOpt false "Whether or not to enable common nix utilities.";
  };

  config = mkIf cfg.enable {
    programs = {
      nix-ld.enable = true;      
    };

    home = {
      packages = with pkgs; [
          nix-prefetch-git
          nix-prefetch-github
          nix-search-cli
      ];

      shellAliases = {
      };
    };

  };
}
