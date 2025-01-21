{
  lib,
  pkgs,
  inputs,
  namespace,
  config,
  options,
  ...
}:
with lib;
with lib.${namespace};
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  projectinitiative = {
    suites = {
      development = enabled;
    };
  };

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

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
  # fonts.packages = with pkgs; [
  #   fira-code
  #   fira-code-symbols
  # ];

  # System-wide packages
  environment.systemPackages = with pkgs; [
    appimage-run
    # displaylink
    # quickemu
    # quickgui
    solaar
    tailscale
    virtualbox
    gnome-firmware
    gnome-network-displays
    # gnome-tweaks
    gnomeExtensions.another-window-session-manager
    gnomeExtensions.appindicator
    gnomeExtensions.dash-to-dock
    gnomeExtensions.pop-shell
    gnomeExtensions.quake-terminal
  ];

  # Enable zsh system-wide
  programs.zsh.enable = true;
  services.fwupd.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
