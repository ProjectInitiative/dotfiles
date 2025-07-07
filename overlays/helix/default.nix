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

  # custom build
  # helix =
  #   let
  #     helixSrc = final.fetchFromGitHub {
  #       owner = "helix-editor";
  #       repo = "helix";
  #       rev = "a63a2ad281b5f651effd29efa4e34f504507d0da"; # Replace with desired commit hash
  #       sha256 = "sha256-a6VO9JFCif+4ipdszBcQO772QLmBtj9Ai5iAgi/4+/U="; # Replace with correct hash
  #     };

  #     # Use `flake-compat` to evaluate the flake
  #     helixFlake =
  #       (import inputs.flake-compat {
  #         src = helixSrc;
  #       }).defaultNix;
  #   in
  #   helixFlake.packages.${final.system}.default;

}
