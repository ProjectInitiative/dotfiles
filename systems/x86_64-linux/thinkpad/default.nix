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
let
  sops = config.sops;
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  sops.secrets = mkMerge [
    {
      restic_password = {
        sopsFile = ./secrets.enc.yaml;
      };
      restic_environment_file = {
        sopsFile = ./secrets.enc.yaml;
      };
    }
  ];

  # enable displaylink
  services.xserver.videoDrivers = [
    "displaylink"
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
  services.restic.backups = {
    home = {
      paths = [ "/home/kylepzak" ];
      exclude = [
        "/home/kylepzak/lost+found"
        "**/target" # Rust build artifacts
        "/home/kylepzak/Downloads"

        # --- System & Filesystem ---
        "/home/kylepzak/.bcachefs_automated_snapshots"

        # --- General Caches ---
        "/home/kylepzak/.cache"
        "/home/kylepzak/.cargo.bak"
        "**/*cache*" # Broadly catch cache-named dirs

        # --- Package Managers & Toolchains ---
        "/home/kylepzak/go/pkg/mod"
        "/home/kylepzak/.npm"
        "/home/kylepzak/.nvm"
        "/home/kylepzak/.rustup"
        "/home/kylepzak/.cargo/registry"
        "/home/kylepzak/.platformio"
        "**/node_modules"
        "**/.venv"

        # --- Runtimes & Sandboxes ---
        "/home/kylepzak/.local/share/flatpak"
        "/home/kylepzak/.var/app"
        "/home/kylepzak/snap"

        # --- Virtualization & Containers ---
        "/home/kylepzak/.docker"
        "/home/kylepzak/.minikube"
        "/home/kylepzak/.vagrant.d/boxes"
        "/home/kylepzak/.local/share/libvirt"

        # --- Application Caches ---
        "/home/kylepzak/.mozilla"
        "/home/kylepzak/.thunderbird"
        "/home/kylepzak/.steam"
        "/home/kylepzak/.android/avd"
        "/home/kylepzak/.vscode/extensions"
        "/home/kylepzak/.vscode-server"
        "/home/kylepzak/.zcompdump*"

        # --- Temporary / Log Files ---
        "/home/kylepzak/.local/share/probe-rs/*.log"
        "**/*.log"
        "**/*.sock"
      ];
      repository = "s3:http://172.16.1.50:31292/laptop-backup/home";
      passwordFile = sops.secrets.restic_password.path;
      environmentFile = sops.secrets.restic_environment_file.path;
      initialize = true;
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
        "--keep-yearly 75"
      ];
      extraBackupArgs = [ "--verbose" ];
    };
    void = {
      paths = [ "/void" ];
      exclude = [
        # lost and found
        "/void/lost+found"
        # snapshots
        "/void/.bcachefs_automated_snapshots"
      ];
      repository = "s3:http://172.16.1.50:31292/laptop-backup/void";
      passwordFile = sops.secrets.restic_password.path;
      environmentFile = sops.secrets.restic_environment_file.path;
      initialize = true;
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
        "--keep-yearly 75"
      ];
      extraBackupArgs = [ "--verbose" ];
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
