{ channels, inputs, ... }:
final: prev: {
  # Just use the version from the channels.nixpkgs that you've provided
   inherit (channels.unstable) zellij;
  }
