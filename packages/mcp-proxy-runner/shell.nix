{
  pkgs ? import <nixpkgs> { },
}:
let
  mcp-proxy = pkgs.callPackage ./default.nix { };

in
pkgs.mkShell {
  packages = [
    mcp-proxy
  ];
}
