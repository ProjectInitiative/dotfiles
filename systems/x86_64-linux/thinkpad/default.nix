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

  # enable numlock during boot
  systemd.services.numLockOnTty = {
    description = "Enable numlock on TTYs";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.writeShellScript "numLockOnTty" ''
        for tty in /dev/tty{1..6}; do
          ${pkgs.kbd}/bin/setleds -D +num < "$tty"
        done
      ''}";
      Type = "oneshot";
      RemainAfterExit = "yes";
    };
  };

  sops.secrets = mkMerge [
    {
      restic_password = {
        sopsFile = ./secrets.enc.yaml;
      };
      restic_environment_file = {
        sopsFile = ./secrets.enc.yaml;
      };
      netbird_setup_key = {
        sopsFile = ./secrets.enc.yaml;
        mode = "0400";
      };

      
      /* # TODO: remove this and add to suite
      aws-nix-cache-push-id = {
        sopsFile = ../../../modules/common/encrypted/secrets/secrets.enc.yaml;
      };
      aws-nix-cache-push-key = {
        sopsFile = ../../../modules/common/encrypted/secrets/secrets.enc.yaml;
      };
      aws-nix-cache-pull-id = {
        sopsFile = ../../../modules/common/encrypted/secrets/secrets.enc.yaml;
      };
      aws-nix-cache-pull-key = {
        sopsFile = ../../../modules/common/encrypted/secrets/secrets.enc.yaml;
      };


      nix-cache-signing-key = {
        sopsFile = ../../../modules/common/encrypted/secrets/secrets.enc.yaml;
      }; */
    }
  ];

  /* systemd.tmpfiles.rules = [
  "L+ /root/.aws/credentials - - - - ${config.sops.templates.aws-creds.path}"
]; */


  /* sops.templates."aws-credentials.ini" = {
    mode = "0444"; 
    content = ''
      [nix-cache-puller]
      aws_access_key_id=${config.sops.placeholder.aws-nix-cache-pull-id}
      aws_secret_access_key=${config.sops.placeholder.aws-nix-cache-pull-key}
      [nix-cache-pusher]
      aws_access_key_id=${config.sops.placeholder.aws-nix-cache-push-id}
      aws_secret_access_key=${config.sops.placeholder.aws-nix-cache-push-key}
    '';
  }; */

  /* sops.templates.aws-creds = {
    mode = "0444"; 
    content = ''
      [nix-cache-puller]
      aws_access_key_id=${config.sops.placeholder.aws-nix-cache-pull-id}
      aws_secret_access_key=${config.sops.placeholder.aws-nix-cache-pull-key}
      [nix-cache-pusher]
      aws_access_key_id=${config.sops.placeholder.aws-nix-cache-push-id}
      aws_secret_access_key=${config.sops.placeholder.aws-nix-cache-push-key}
    '';
  }; */

  /* nix = {
    envVars = {
      AWS_SHARED_CREDENTIALS_FILE = config.sops.templates."aws-credentials.ini".path;
    };


    # extraOptions = ''
    #   access-tokens = s3-nix-cache-test:file://${config.sops.templates."aws-credentials.ini".path}
    # '';
    settings = {

      substituters = [
        # Pusher
        # "s3://nix-cache-test?region=us-east-1&endpoint=http://172.16.1.50:31292&profile=nix-cache-pusher"
        # "s3://nix-cache?region=us-east-1&endpoint=http://172.16.1.50:31292&profile=nix-cache-pusher"

        # Puller
        "s3://nix-cache?region=us-east-1&endpoint=http://172.16.1.50:31292&profile=nix-cache-puller"
        # "s3://nix-cache-test?region=us-east-1&endpoint=http://172.16.1.50:31292&profile=nix-cache-puller"

        # "s3://nix-cache-test?region=us-east-1&endpoint=http://172.16.1.50:31292&profile=nix-cache-puller&readonly=1"
        # "s3://nix-cache-test?region=us-east-1&profile=nix-cache-puller&endpoint=http://172.16.1.50:31292"
        # "s3://nix-cache-test?endpoint=http://172.16.1.50:31292"
      ];
      trusted-public-keys = [
        "nix-cache:S7lSpN8xTtMELxw2cBl9nq4hEv2nCSShIe1re3P/q/s="
      ];
    };
  }; */


  # nixpkgs.overlays = [
  #   (final: prev: {
  #     netbird = prev.netbird.overrideAttrs (oldAttrs: rec {
  #       version = "0.54.2";
  #       src = prev.fetchFromGitHub {
  #         owner = "projectinitiative";
  #         repo = "netbird";
  #         rev = "53f3cefd4f1a6751f064bda2ccc870005c311386";
  #         hash = "sha256-AiVACuzTyLX0qGRCOLC655IOJKz75UjluqDiRRnCq40=";
  #         # owner = "netbirdio";
  #         # repo = "netbird";
  #         # rev = "v${version}";
  #         # hash = "sha256-1xCaH29CweLxbOXyesxDc3vBkvHo5aQr4icyf/8VwJk=";
  #       };
  #       vendorHash = "sha256-zpZZdkEqYYmojd5M74jPOaSdt8uvv80XGLH/CmfjWLg=";
  #     });
  #   })
  # ];

  # # Create environment file using sops template
  # sops.templates.netbird-env = {
  #   content = ''
  #     NB_SETUP_KEY=${config.sops.placeholder.netbird_setup_key}
  #   '';
  #   mode = "0400";
  #   owner = "root";  # Match the service user
  # };

  # services.netbird = {
  #   enable = false;
  #   clients.default = {
  #     port = 51820;
  #     interface = "wt0";
  #     name = "netbird";
  #     hardened = false;

  #     config = {
  #       DisableDNS = true;
  #       DisableFirewall = true;
  #     };
  #   };
  # };

  # # Add the environment file to the systemd service
  # # This will make NB_SETUP_KEY available to the netbird process
  # # TODO: Figure out why this isn't working
  # systemd.services.netbird.serviceConfig.EnvironmentFile = [
  #   config.sops.templates.netbird-env.path
  # ];

  # # Override the ExecStart to include the setup key file
  # # systemd.services.netbird.serviceConfig.ExecStart = lib.mkForce ''
  # #   ${config.services.netbird.clients.default.wrapper}/bin/netbird service run \
  # #     --setup-key-file ${config.sops.secrets.netbird_setup_key.path}
  # # '';

  # services.comin =
  #   let
  #     livelinessCheck = pkgs.writeShellApplication {
  #       name = "comin-liveliness-check";
  #       runtimeInputs = [ pkgs.iputils ];
  #       text = ''
  #         ping -c 5 google.com
  #         # curl --fail http://localhost:8080/health
  #       '';
  #     };
  #   in
  #   {
  #     enable = true;
  #     remotes = [{
  #       name = "origin";
  #       url = "https://github.com/projectinitiative/dotfiles.git";
  #       branches.main.name = "main";
  #     }];
  #     livelinessCheckCommand = "${livelinessCheck}/bin/comin-liveliness-check";
  #   };

  # # enable displaylink
  # services.xserver.videoDrivers = [
  #   # "displaylink"
  #   "modesetting"
  # ];

  # add second monitor
  services.xserver.displayManager.sessionCommands = ''
    ${lib.getBin pkgs.xorg.xrandr}/bin/xrandr --setprovideroutputsource 2 0
  '';

  virtualisation.docker.extraOptions="--insecure-registry 172.16.1.50:31872";

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

    #   bcachefs-kernel = {
    #     enable = true;
    #     # rev = "09e0711c260f1d14dd439315465c495003e02b4f";
    #     # hash = "sha256-jSN8o7XxbSY/o3gyVsDtYPWGnsQedeLAI8ZzgjNJuuE=";

    #     # TODO: fix pinning kernel for evdi compat
    #     rev = "63ea3cf07639ec8ef5bd2c3f457eb54b6cd33198";
    #     hash = "sha256-dY0yb0ZO0L5zOdloasqyEU80bitr1VNdmoyvxJv/sYE=";

    #     # rev = "";
    #     # hash = "";
    #     debug = true;
    #   };
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
        loft = {
          enable = true;
          enableClient = true;
          enableServer = true;
        };
        attic = {
          enableClient = mkForce false;
        };
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
    smartmontools
    bitwarden-desktop
    solaar
    # spotify
    mtr
    # virtualbox
    vlc
    wireshark
    mqttx
    mqttui
    wireshark-qt
    networkmanagerapplet
    ## temp
    minicom
    rkdeveloptool
    flashrom

    multipath-tools
    usbutils

    wine64
    winetricks
    wineWowPackages.waylandFull

    ani-cli
    stremio-linux-shell
    # pkgs.${namespace}.stremio-linux-shell
    obs-studio

    pkgs.${namespace}.mcp-proxy-runner
    # gst_all_1.gst-plugins-rs

    alsa-utils # for alsamixer
    pavucontrol # for PipeWire profile control

    yubikey-manager
    yubioath-flutter
    # yubikey-personalization
    # yubikey-personalization-gui

    openbao
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

  programs.adb.enable = true;
  users.users.kylepzak.extraGroups = [ "tss" "adbusers" ]; # tss group has access to TPM devices


  # rtkit is optional but recommended
  security.rtkit.enable = true;
  services.pipewire = {
    enable = mkForce true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.extraConfig.bluetoothEnhancements = {
      "monitor.bluez.properties" = {
        "bluez5.codecs" = "[ sbc sbc_xq aac ldac aptx aptx_hd ]";
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles" = [ "hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag" "a2dp_sink" "a2dp_source" ];
      };
    };
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;

  # Ensure ALSA hardware layer is enabled
  hardware.alsa.enable = true;

  # Install firmware for Intel SOF devices
  hardware.firmware = [ pkgs.sof-firmware ];

  # Force snd_hda_intel instead of SOF
  boot.extraModprobeConfig = ''
    options snd-intel-dspcfg dsp_driver=1
  '';

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  # system.stateVersion = "24.11"; # Did you read the comment?

  specialisation.safe = {
    configuration = {
      system.stateVersion = "25.05";
      fileSystems = lib.mkForce {
        "/" = {
          device = "/dev/disk/by-uuid/04f9ecc2-bb20-415f-aff5-c54285523fd3";
          fsType = "ext4";
        };
        "/boot" = {
          device = "/dev/disk/by-partuuid/05399427-3ed0-4da7-bd08-740ddb6ce486";
          fsType = "vfat";
        };
        "/home/kylepzak" = {
          fsType = "tmpfs";
          options = [ "defaults" "size=2g" ];
        };
      };
    };
  };
}
