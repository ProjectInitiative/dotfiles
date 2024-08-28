{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome = {
    enable = true;
    extraGSettingsOverrides = ''
      [org.gnome.mutter]
      edge-tiling=true
      [org.gnome.desktop.wm.preferences]
      button-layout=':minimize,maximize,close'
    '';
  };

  # Enable GNOME Shell extensions for all users
  environment.sessionVariables = {
    GNOME_SHELL_EXTENSIONS = with pkgs.gnomeExtensions; [
      "${dash-to-dock}/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com"
      "${quake-mode}/share/gnome-shell/extensions/quake-mode@repsac-by.github.com"
      "${pop-shell}/share/gnome-shell/extensions/pop-shell@system76.com"
    ];
  };

  # Install fonts
  fonts.packages = with pkgs; [
    fira-code
    fira-code-symbols
  ];

  # System-wide packages
  environment.systemPackages = with pkgs; [
    # displaylink
    gnome-tweaks
    gnomeExtensions.dash-to-dock
    gnomeExtensions.quake-terminal
    gnomeExtensions.pop-shell
  ];

  # Enable zsh system-wide
  programs.zsh.enable = true;

  # This setting is handled in the common configuration, but you can override it here if needed
  # users.users.kylepzak.shell = pkgs.zsh;

  # Any ThinkPad-specific hardware configurations can go here
  # For example, if you need to enable specific kernel modules or set hardware-specific options

  # If you have any ThinkPad-specific services or settings, add them here
}
