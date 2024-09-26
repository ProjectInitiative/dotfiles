{ config, lib, pkgs, ... }:

{
  # imports =
  #   [ # Include the results of the hardware scan.
  #     ./hardware-configuration.nix
  #   ];

    # nixpkgs.overlays = [
    #   (import ./overlays.nix)
    # ];


  # System-wide packages
  environment.systemPackages = with pkgs; [
    docker-compose
    podman-compose
    tailscale
    nvidia-docker
    # nvidia-podman
    nvidia-container-toolkit
    cudatoolkit
    linuxPackages.nvidia_x11
  ];

  # Enable zsh system-wide
  programs.zsh.enable = true;

  # This setting is handled in the common configuration, but you can override it here if needed
  # users.users.kylepzak.shell = pkgs.zsh;

  # Any ThinkPad-specific hardware configurations can go here
  # For example, if you need to enable specific kernel modules or set hardware-specific options

  # If you have any ThinkPad-specific services or settings, add them here
}
