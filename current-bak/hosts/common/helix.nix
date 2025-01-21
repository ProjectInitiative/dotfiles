{
  pkgs ? import <nixpkgs> { },
}:

let
  helixSrc = pkgs.fetchFromGitHub {
    owner = "helix-editor";
    repo = "helix";
    rev = "57ec3b7330de3f5a7b37e766a758f13fdf3c0da5"; # Replace with the specific commit hash
    sha256 = "sha256-10PtZHgDq7S5n8ez0iT9eLWvAlEDtEi572yFzidLW/0="; # Replace with the correct hash
  };

  helixPkgs = import (helixSrc + "/flake.nix") {
    inherit pkgs;
    inputs.nixpkgs.follows = "nixpkgs";
  };
in
helixPkgs.packages.helix
