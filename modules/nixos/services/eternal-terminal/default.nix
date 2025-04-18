# eternal-terminal.nix

{ config, lib, pkgs, namespace, ... }:

with lib;

let
  # Define a shorthand for the configuration options of this module
  cfg = config.${namespace}.services.eternal-terminal;
in
{
  # Define the options that users can configure
  options.${namespace}.services.eternal-terminal = {
    enable = mkEnableOption "Eternal Terminal client";

    enableServer = mkOption {
      type = types.bool;
      default = true;
      description = "Eternal Terminal server daemon";
    };

    port = mkOption {
      type = types.port; # Use types.port for validating port numbers
      default = 2022;
      description = "Port for the etserver daemon to listen on.";
    };

    openFirewall = mkOption {
       type = types.bool;
       # Default to true if the service is enabled, false otherwise.
       # Users often expect a service listening on a port to have its firewall opened.
       default = cfg.enable;
       description = "Whether to automatically open the firewall port for etserver.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "--verbose" ];
      description = "Extra command-line arguments to pass to the etserver daemon.";
    };

    # Add more options here if needed, e.g., User, Group, CfgFile path
    # user = mkOption { ... };
    # group = mkOption { ... };
  };

  # Define the actual system configuration based on the options
  config = mkIf cfg.enable {

    environment.systemPackages = with pkgs; [
      eternal-terminal
    ];

    # Define the systemd service for etserver
    systemd.services.eternal-terminal = mkIf cfg.enableServer {
      description = "Eternal Terminal Server Daemon";
      # Start after the network is ready
      after = [ "network.target" ];
      # Ensure it's started on boot in the multi-user target
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        # Consider creating a dedicated user/group for etserver for better security
        # User = cfg.user;
        # Group = cfg.group;
        User = "root"; # Running as root is common for services binding low ports or needing privileges
        Group = "root"; # Or use "nogroup" / dedicated group
        Restart = "on-failure"; # Restart the service if it fails
        RestartSec = "5s";

        # Construct the command to start etserver
        # Use the specified package, port, and any extra arguments
        ExecStart = ''
          ${pkgs.eternal-terminal}/bin/etserver \
            --port=${toString cfg.port} \
            ${escapeShellArgs cfg.extraArgs}
        '';

        # Basic Systemd Hardening Options (optional but recommended)
        # AmbientCapabilities = "";
        # CapabilityBoundingSet = "";
        # LockPersonality = true;
        # NoNewPrivileges = true;
        # PrivateTmp = true;
        # ProtectSystem = "strict";
        # ProtectHome = true; # May need to be false if etserver needs home dir access
        # ProtectClock = true;
        # ProtectControlGroups = true;
        # ProtectKernelLogs = true;
        # ProtectKernelModules = true;
        # ProtectKernelTunables = true;
        # RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ]; # et uses IP protocols
        # RestrictNamespaces = true;
        # RestrictRealtime = true;
        # SystemCallArchitectures = "native";
        # UMask = "0077";
      };
    };

    # Conditionally open the firewall port if openFirewall is true
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

    # If you added user/group options, you might define them here:
    # users.users.${cfg.user} = { isSystemUser = true; group = cfg.group; };
    # users.groups.${cfg.group} = { members = [ cfg.user ]; };
  };
}
