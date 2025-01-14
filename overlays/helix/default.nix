{ channels, ... }:

final: prev: {

  helix-test = let
    helixSrc = final.fetchFromGitHub {
      owner = "helix-editor";
      repo = "helix";
      rev = "57ec3b7330de3f5a7b37e766a758f13fdf3c0da5";  # Replace with desired commit hash
      sha256 = "sha256-10PtZHgDq7S5n8ez0iT9eLWvAlEDtEi572yFzidLW/0=";  # Replace with correct hash
    };
    
    helixFlake = import (helixSrc + "/flake.nix") {
      # We use `final` instead of `pkgs` to properly handle the overlay chain
      pkgs = final;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  in helixFlake.packages.${final.system}.default;
}

