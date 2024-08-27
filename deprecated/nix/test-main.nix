# /etc/nixos/configuration.nix

{ config, pkgs, ... }:

{
   system.stateVersion = "23.11";

  environment.systemPackages = with pkgs; [
    # Include other necessary packages
		 nixos-install-tools
  ];

  imports =
    [
      # Include the service to dynamically generate the configuration
      ./generate-config.nix
    ];

  # Your other NixOS configuration options...
}
