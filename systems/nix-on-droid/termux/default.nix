{ config, lib, pkgs, ... }:

{
  system.stateVersion = "24.05";

  environment.packages = with pkgs; [
    vim
    git
    openssh
    man
  ];

  # Configure home-manager
  home-manager.config = { pkgs, ... }: {
    home.stateVersion = "24.05";
    
    # Simple default configuration
    home.packages = with pkgs; [
        htop
        ripgrep
        jq
        curl
        wget
    ];
  };
}
