# To use this configuration:
# On a NixOS system:

# Clone the repository
# Run sudo nixos-rebuild switch --flake .#myNixOS

# On a non-NixOS system with Nix installed:

# Clone the repository
# For home-manager: Run home-manager switch --flake .#myuser
# To just install packages: Run nix-env -f packages/default.nix -i

# For a quick environment with all packages:
# Run nix-shell -p '(import ./packages/default.nix {})'


# packages/default.nix
{ pkgs ? import <nixpkgs> {} }:

import ./common.nix { inherit pkgs; }

