{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.cargohold;
in
{
  options.${namespace}.hosts.cargohold = {
    enable = mkBoolOpt false "Whether to enable base cargohold NAS configuration";
    ipAddress = mkOpt types.str "192.168.1.100/24" "Static management IP address with CIDR"; # Example IP
    interface = mkOpt types.str "eth0" "Network interface for static IP"; # Example interface
    gateway = mkOpt types.str "192.168.1.1" "Default gateway"; # Example gateway
    bcachefsMountpoint = mkOpt types.str "/mnt/storage" "Path to mount bcachefs pool";
    # Add more NAS specific options here later if needed (e.g., Samba shares)
  };

  config = mkIf cfg.enable (
    # Reference the kernel package being used
    let
      kernel = config.boot.kernelPackages.kernel; # Use the kernel defined below or default

      # Fetch the source for the it87 driver
      # !!! REPLACE owner, repo, rev, and sha256 with actual values !!!
      it87-driver-src = pkgs.fetchFromGitHub {
        owner = "frankcrawford";
        repo = "it87";
        rev = "4bff981a91bf9209b52e30ee24ca39df163a8bcd";
        hash = "sha256-hjNph67pUaeL4kw3cacSz/sAvWMcoN2R7puiHWmRObM=";
      };

      # Define the package to build the kernel module
      it87-driver = config.boot.kernelPackages.callPackage ({ stdenv, lib }:
        let
          # Define correct paths from Nix environment
          kernelBuildDir = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
          moduleInstallDir = "${placeholder "out"}/lib/modules/${kernel.modDirVersion}/kernel/drivers/hwmon"; # Matches Makefile's MOD_SUBDIR
        in
        stdenv.mkDerivation {
          pname = "it87-out-of-tree";
          version = "${kernel.version}-${lib.substring 0 7 it87-driver-src.rev}";

          src = it87-driver-src;

          nativeBuildInputs = kernel.moduleBuildDependencies;


          # Explicitly define build phase, overriding Makefile's KERNEL_BUILD calculation
          buildPhase = ''
            runHook preBuild
            echo "--- Building IT87 module ---"
            echo "Overriding KERNEL_BUILD=${kernelBuildDir}"
            # Pass KERNEL_BUILD directly to the make command for the 'modules' target.
            # This ensures the '-C' argument in that target uses the correct path.
            # Also pass M=$PWD explicitly.
            make modules KERNEL_BUILD="${kernelBuildDir}" M="$PWD"
            echo "--- Finished building IT87 module ---"
            runHook postBuild
          '';

          # Explicitly define install phase, bypassing Makefile's install target
          installPhase = ''
            runHook preInstall
            echo "--- Installing IT87 module manually ---"
            # Create the correct destination directory inside $out
            mkdir -p "${moduleInstallDir}"
            # Copy the built module (assuming name is it87.ko based on Makefile)
            cp it87.ko "${moduleInstallDir}/"
            echo "Installed it87.ko to ${moduleInstallDir}"
            # DO NOT RUN depmod. NixOS handles module dependencies.
            runHook postInstall
          '';

          meta = with lib; {
            description = "Out-of-tree kernel module for ITE IT8xxx Super I/O chips (inc. IT8613E)";
            license = licenses.gpl2Only; # Verify license
            platforms = platforms.linux;
            maintainers = [ maintainers.kylepzak ];          };
        }) { }; # Pass empty attribute set for callPackage

    in {
    # Base system packages
    environment.systemPackages = with pkgs; [
      bcachefs-tools
      smartmontools
      lsof
      pciutils
      iperf3
      lm_sensors
      # Add NAS related tools like samba, nfs-utils if needed
    ];

    # Enable bcachefs support
    boot.supportedFilesystems = [ "bcachefs" ];

    boot.kernelModules = [ "bcachefs" "it87" ];
    # Consider using latest kernel if needed for bcachefs features
    boot.kernelPackages = pkgs.linuxPackages_latest;
    # Add the out-of-tree module package here
    boot.extraModulePackages = [ it87-driver ];
    
    boot.kernelParams = [ "nomodeset" ];

    console.enable = true;
    # enable GPU drivers
    hardware.enableRedistributableFirmware = true;
    hardware.firmware = [ pkgs.linux-firmware ];

    # Enable SSH access
    services.openssh = {
      enable = true;
      settings = {
      };
    };

    # Networking using systemd-networkd
    networking = {
      useDHCP = true; # Disable global DHCP
      # interfaces = { }; # Clear interfaces managed elsewhere
      nameservers = [
        cfg.gateway # Use gateway as primary DNS
        "1.1.1.1" # Cloudflare DNS
        "9.9.9.9" # Quad9 DNS
      ];
      # defaultGateway = cfg.gateway; # Set via systemd-networkd route
      # firewall.allowedTCPPorts = [
      #   22 # SSH
      #   5201 # iperf
      #   # Add ports for NAS services (e.g., Samba: 139, 445)
      # ];
      networkmanager.enable = false; # Ensure NetworkManager is disabled
    };

    systemd.network = {
      enable = false;
      networks."10-${cfg.interface}" = {
        matchConfig.Name = cfg.interface;
        networkConfig = {
          DHCP = "no";
          Address = cfg.ipAddress;
          Gateway = cfg.gateway;
          DNS = config.networking.nameservers; # Use nameservers defined above
          IPv6AcceptRA = "no";
        };
        # Explicit default route
        routes = [
          {
            Gateway = cfg.gateway;
            Destination = "0.0.0.0/0";
          }
        ];
      };
    };

    # Enable common project modules if needed
    projectinitiative = {
      services = {     

        eternal-terminal = enabled;

        health-reporter = {
          enable = true;
          telegramTokenPath = config.sops.secrets.health_reporter_bot_api_token.path;
          telegramChatIdPath = config.sops.secrets.telegram_chat_id.path;
          excludeDrives = [
            "loop"
            "ram"
            "sr"
          ]; # Default exclusions
          reportTime = "08:00"; # Send report at 8 AM
        };
      };
      suites = {
        bcachefs-utils = enabled;
      };
      system = {
        console-info.ip-display = enabled;

        bcachefs-kernel = {
          enable = true;
          branch = "c79cf4111930c22487840d1332ee1d44e1c31707"; # Or specify a specific commit hash
          sourceHash = "sha256-uVo7X8/1akJxgO0ERu/41+XmK7l1uRAZuKYJV4mNQAo=";
          debug = true;
        };
        bcachefs-module = {
          enable = false;
          rev = ""; # Or specify a specific commit hash
          hash = "";
          debug = true;
        };

      };
      networking.tailscale = {
        enable = true; # Example: Enable Tailscale
        ephemeral = false;
        extraArgs = [ "--accept-routes" ];
      };
      # Add other services like Samba, NFS configuration here
      # services.samba = { enable = true; /* ... */ };
    };

    # Set the state version
    system.stateVersion = "24.05"; # Adjust as needed
    }
  );
}
