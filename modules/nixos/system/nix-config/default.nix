{
  options,
  config,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.system.nix-config;
in
{
  options.${namespace}.system.nix-config = with types; {
    enable = mkBoolOpt false "Whether or not to manage nix-config settings.";
  };

  config = mkIf cfg.enable {
    nix = {
      # package = pkgs.nixVersions.nix_2_25;
      gc = {
        automatic = true;
        dates = "weekly";
        persistent = true;
        options = "--delete-older-than 30d";
      };
      settings = {
        auto-optimise-store = true;
      };
      extraOptions = ''
        min-free = ${toString (100 * 1024 * 1024)}
        max-free = ${toString (1024 * 1024 * 1024)}
      '';
    };
  };
}
