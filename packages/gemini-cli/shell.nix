
{
  pkgs ? import <nixpkgs> { },
}:
let
  gemini-cli = pkgs.callPackage ./default.nix {};

  in
  pkgs.mkShell {
    packages = [
      gemini-cli
    ];
  }
