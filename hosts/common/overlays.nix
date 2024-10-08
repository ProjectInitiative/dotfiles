flakeRoot: final: prev: {
  # helix = final.callPackage ./helix.nix { };
  freecad = prev.freecad.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or []) ++ [
      ( flakeRoot + "/pkgs/custom/freecad/0003-fix-cursor-font-bug.patch")
    ];
  });
}
# final: prev: {
#   helix = (final.callPackage
#     ({ fetchFromGitHub }: 
#       let
#         helix-src = fetchFromGitHub {
#           owner = "helix-editor";
#           repo = "helix";
#           rev = "57ec3b7330de3f5a7b37e766a758f13fdf3c0da5";  # Replace with desired commit
#           sha256 = "sha256-10PtZHgDq7S5n8ez0iT9eLWvAlEDtEi572yFzidLW/0=";  # Update this hash
#         };
#         helix-flake = final.callPackage (import "${helix-src}/flake.nix") {};
#       in
#         helix-flake.packages.${prev.system}.default
#     ) {});

#   # Additional overrides as needed
# }
# final: prev: {
#   helix = (final.callPackage
#     ({ fetchFromGitHub }: fetchFromGitHub {
#       owner = "helix-editor";
#       repo = "helix";
#       rev = "57ec3b7330de3f5a7b37e766a758f13fdf3c0da5";  # Replace with desired commit
#       sha256 = "sha256-10PtZHgDq7S5n8ez0iT9eLWvAlEDtEi572yFzidLW/0=";  # Update this hash
#     }) {}).defaultPackage.${prev.system};

#   # Additional overrides as needed
# }
# final: prev: {
#   helix = (final.callPackage
#     ({ fetchFromGitHub }: let
#       helix-src = fetchFromGitHub {
#         owner = "helix-editor";
#         repo = "helix";
#         rev = "57ec3b7330de3f5a7b37e766a758f13fdf3c0da5";  # Replace with desired commit
#         sha256 = "sha256-10PtZHgDq7S5n8ez0iT9eLWvAlEDtEi572yFzidLW/0=";  # Update this hash
#       };
#     in (final.lib.importFlake helix-src).packages.${prev.system}.default
#     ) {});

#   # Additional overrides as needed
# }
