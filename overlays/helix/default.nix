{ channels, inputs, ... }:

final: prev: {
  helix =
    let
      helixSrc = final.fetchFromGitHub {
        owner = "helix-editor";
        repo = "helix";
        rev = "e7ac2fcdecfdbf43a4f772e7f7c163b43b3d0b9b"; # Replace with desired commit hash
        sha256 = "sha256-wGfX2YcD9Hyqi7sQ8FSqUbN8/Rhftp01YyHoTWYPL8U="; # Replace with correct hash
      };

      # Use `flake-compat` to evaluate the flake
      helixFlake =
        (import inputs.flake-compat {
          src = helixSrc;
        }).defaultNix;
    in
    helixFlake.packages.${final.system}.default;

  #   helixFlake = import (helixSrc + "/flake.nix") {
  #     # We use `final` instead of `pkgs` to properly handle the overlay chain
  #     pkgs = final;
  #     inputs.nixpkgs.follows = "nixpkgs";
  #   };
  # in
  # helixFlake.packages.${final.system}.default;
}
