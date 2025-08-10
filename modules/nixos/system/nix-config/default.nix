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
  nix-public-signing-key = "tugboat:r+QK20NgKO/RisjxQ8rtxctsc5kQfY5DFCgGqvbmNYc=";
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
        # add binary cache key
        # Individual build servers that are authorized to push remote builds.
        # See sops.yaml nix-signing
        trusted-public-keys = mkMerge [ [ nix-public-signing-key ] ];
      };
      extraOptions = ''
        min-free = ${toString (100 * 1024 * 1024)}
        max-free = ${toString (1024 * 1024 * 1024)}
      '';
    };
  };
}
