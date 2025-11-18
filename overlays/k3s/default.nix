{ channels, inputs, ... }:
final: prev: {
  # Just use the version from the channels.nixpkgs that you've provided
  inherit (channels.nixpkgs-catch-up) k3s;
}
