{
  description = "Nixpkgs with custom inputs and overrides";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    helix.url = "github:helix-editor/helix/162028d444b1e56ee39775460adb65e4f957bc3f";
  };
  outputs = { self, nixpkgs, helix, ... }: 
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
        overlays = [
          (final: prev: {
            helix = builtins.trace "Evaluating Helix overlay" (
              builtins.trace "Helix version: ${helix.packages.${system}.default.version}"
              helix.packages.${system}.default
            );
          })
        ];
      };
    in {
      pkgs = builtins.trace "Returning pkgs from pkgs/flake.nix" pkgs;
      lib = nixpkgs.lib;
    };
}
