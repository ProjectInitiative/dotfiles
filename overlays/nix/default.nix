{ channels, inputs, ... }:

final: prev: {
  # nix = prev.nix.overrideAttrs (oldAttrs: {
  #   src = final.fetchFromGitHub {
  #     owner = "NixOS";
  #     repo = "nix";
  #     rev = "36bd92736faaf81c6af3dff8f560963eb4e76b14";
  #     hash = "sha256-1T7WRNfUMsiiNB77BuHElzjavguL8oJx+wBtfMcobq8=";
  #   };
  #   version = "${oldAttrs.version}-36bd927"; # Append commit hash to version
  # });
  # nix =
  #   let
  #     nixSrc = final.fetchFromGitHub {
  #       owner = "NixOS";
  #       repo = "nix";
  #       # rev = "d9775222fbfa7e5d8ce1f722ea2968ff840324b4";
  #       # hash = "sha256-b7smrbPLP/wcoBFCJ8j1UDNj0p4jiKT/6mNlDdlrOXA=";
  #       # 
  #       # rev = "28752fe28868f2c1a4d3c8a86a1ada94b99cce35";
  #       # hash = "sha256-0lFNh54gkDsdHOriOEHK6lr1rGRiP1mhNaCNm+6QspE=";

  #       "rev"= "36bd92736faaf81c6af3dff8f560963eb4e76b14";
  #       "hash"= "sha256-1T7WRNfUMsiiNB77BuHElzjavguL8oJx+wBtfMcobq8=";
  #     };

  #   nixFlake = (import inputs.flake-compat {
  #       src = nixSrc;
  #     }).defaultNix;
  #     inherit (prev) nix;  # Get the original nix package for meta
  #   in
  #   nixFlake.packages.${final.system}.nix // { inherit (nix) meta; };

    #   # Use `flake-compat` to evaluate the flake
    #   nixFlake =
    #     (import inputs.flake-compat {
    #       src = nixSrc;
    #     }).defaultNix;
    # in
    # nixFlake.packages.${final.system}.default;

}
