# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  stateVersion,
  config,
  lib,
  pkgs,
  ssh-pub-keys,
  flakeRoot,
  ...
}:

let
  commonDesktopPackages = import (flakeRoot + "/pkgs/common/desktop.nix") { inherit pkgs; };
in
# tempOverlay = self: super: {
#   lsp-ai = self.callPackage ../../pkgs/custom/lsp-ai/package.nix {};
# };
{
  nixpkgs.overlays = [
    (import ./desktop-overlays.nix {
      inherit flakeRoot;
    })
  ];
  # nixpkgs.overlays = [ tempOverlay ];
  # Enable flakes
  # nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # List packages installed in system profile
  environment.systemPackages = commonDesktopPackages;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = stateVersion; # Did you read the comment?
}
