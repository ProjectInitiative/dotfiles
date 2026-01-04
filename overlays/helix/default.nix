{ channels, inputs, ... }:

final: prev: {
  # Just use the version from the channels.nixpkgs that you've provided
  # inherit (channels.unstable) helix;

  # build from source
  helix =
    let
      helixSrc = final.fetchFromGitHub {
        owner = "helix-editor";
        repo = "helix";
        rev = "036729211a94d058b835f5ee212ab15de83bc037";
        hash = "sha256-pPktfkA5r1zhza2Gw+u7K4g/s9EfpXXMh7m/IQ3mIbs=";
      };

      # Use `flake-compat` to evaluate the flake
      helixFlake =
        (import inputs.flake-compat {
          src = helixSrc;
        }).defaultNix;
    in
    helixFlake.packages.${final.stdenv.hostPlatform.system}.default;

}
