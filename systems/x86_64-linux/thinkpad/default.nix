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

  home-manager.backupFileExtension = "backup";

  projectinitiative = {

    # encrypted.nix-signing = enabled;

    gui = {
      gnome = enabled;
    };

    suites = {
      development = enabled;
    };

  };

  # System-wide packages
  environment.systemPackages = with pkgs; [
    # displaylink
    # quickemu
    # quickgui
    bitwarden-desktop
    solaar
    spotify
    mtr
    virtualbox
    vlc
    wireshark
    wireshark-qt
  ];

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
