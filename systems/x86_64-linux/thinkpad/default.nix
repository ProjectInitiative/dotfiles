{
  lib,
  pkgs,
  inputs,
  namespace,
  system,
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

  # enable displaylink
  services.xserver.videoDrivers = [
    # "displaylink"
    "modesetting"
  ];

  # add second monitor
  services.xserver.displayManager.sessionCommands = ''
    ${lib.getBin pkgs.xorg.xrandr}/bin/xrandr --setprovideroutputsource 2 0
  '';

  home-manager = {
    backupFileExtension = "backup";
    users.kylepzak.${namespace} = {
      suites = {
        development.enable = true;
      };
    };

  };

  projectinitiative = {

    settings = {
      stateVersion = "25.05";
    };

    encrypted.nix-signing = enabled;

    system = {
      displaylink.enable = false;
      nix-config = enabled;

      bcachefs-kernel = {
        enable = true;
        # rev = "";
        # hash = "";
        debug = true;
      };
    };

    gui = {
      gnome = enabled;
    };
    services = {
      power-profile-manager = enabled;
      tpm = enabled;
      bcachefsRereplicateAuto.enable = mkForce false;
      bcachefsScrubAuto.enable = mkForce false;
      bcachefsSnapshots = {
        targets = {

          void = {
            parentSubvolume = "/void"; # MANDATORY: Set path for this new target
            readOnlySnapshots = true; # Optional: default is true

            retention = {
              # Define retention for this new target
              hourly = 6;
              daily = 7;
              weekly = 4;
              monthly = 6;
              yearly = 2;
            };
          };
        };
      };

    };

    suites = {
      development = enabled;
      bcachefs-utils = {
        enable = true;
        parentSubvolume = "/home/kylepzak";
      };
    };
    # override
    networking = {
      # tailscale = {

      #   enable = false;
      #   extraArgs = [ "--accept-routes" ];
      # };
    };

  };

  # Make sure NetworkManager is enabled
  networking.networkmanager.enable = true;

  # System-wide packages
  environment.systemPackages = with pkgs; [
    # quickemu
    # quickgui
    bitwarden-desktop
    solaar
    # spotify
    mtr
    virtualbox
    vlc
    wireshark
    mqttx
    mqttui
    wireshark-qt
    networkmanagerapplet
    ## temp
    minicom
    rkdeveloptool
    multipath-tools
    usbutils

    wine64
    winetricks
    wineWowPackages.waylandFull

    ani-cli
    obs-studio

    pkgs.${namespace}.mcp-proxy-runner
    # gst_all_1.gst-plugins-rs
  ];

  # Enable fingerprint reader
  services.fprintd = {
    enable = true;
    tod = {
      enable = true;
      # driver = pkgs.libfprint-2-tod1-vfs0090; # (If the vfs0090 Driver does not work, use the following driver)
      driver = pkgs.libfprint-2-tod1-goodix; # (On my device it only worked with this driver)
    };
  };

  # Enable firmware service
  services.fwupd.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;

  users.users.kylepzak.extraGroups = [ "tss" ]; # tss group has access to TPM devices

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
  # system.stateVersion = "24.11"; # Did you read the comment?
}
