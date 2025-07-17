# ./modules/attic-client.nix (or your preferred path)
{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;

let
  # Use the namespace in the cfg definition
  cfg = config.${namespace}.services.attic.client;
  loginScript = pkgs.writeShellScript "attic-login" ''
    #!/usr/bin/env bash
    # Construct the login command securely
    ${pkgs.attic-client}/bin/attic login \
      ${escapeShellArg cfg.cacheName} \
      ${escapeShellArg cfg.serverUrl} \
      $(cat ${escapeShellArg cfg.apiTokenFile})
  '';
in
{
  # Use the namespace in the options path
  options.${namespace}.services.attic.client = {
    enable = mkEnableOption "Attic client configuration";

    cacheName = mkOption {
      type = types.str;
      description = "Logical name for the Attic cache (e.g., 'mycache'). Must match the name used on the server for the API token.";
      example = "mycache";
    };

    serverUrl = mkOption {
      type = types.str;
      description = "URL of the Attic server (atticd).";
      example = "http://attic.example.com:8080";
    };

    publicKey = mkOption {
      type = types.str;
      description = "Public signing key of the Attic server (obtain from server's /var/lib/atticd/signing-key.pub).";
      example = "attic-cache:your-public-key-here";
    };

    apiTokenFile = mkOption {
      type = types.path; # Expecting a path (likely from agenix/sops-nix)
      description = "Absolute path to the file containing the API token (format: 'attic-token:YOUR_SECRET_TOKEN_HERE').";
      example = "/run/secrets/attic-client-token";
    };

    manageNixConfig = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically add substituter and trusted-public-key to nix.settings.";
    };

    autoLogin = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically log in to the cache on boot/activation using a systemd service.";
    };

    watchStore = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "watching the Nix store and uploading new paths using 'attic watch-store'";
          jobs = mkOption {
            type = types.int;
            default = 5;
            description = "Maximum number of parallel upload processes for watch-store.";
          };
          # Add other watch-store flags as options if needed later
          # ignoreUpstreamCacheFilter = mkOption { type = types.bool; default = false; };
        };
      };
      default = {
        enable = false;
      }; # Default to disabled; user must opt-in
      description = "Configuration for running 'attic watch-store' as a background service.";
    };

  };

  # Define the actual system configuration based on the options
  config = mkIf cfg.enable {
    # 1. Install Attic client package
    # TODO: use flake
    environment.systemPackages = [ pkgs.attic-client ];

    # 2. Add cache to Nix settings if requested (using mkMerge for safety)
    nix = {
      settings = mkIf cfg.manageNixConfig {
        substituters = mkMerge [ [ "${cfg.serverUrl}" ] ];
        trusted-public-keys = mkMerge [ [ cfg.publicKey ] ];
        connect-timeout = 5;
      };
      extraOptions = ''
        # Ensure we can still build when missing-server is not accessible
        fallback = true
      '';
    };

    # 3. Systemd service to log in automatically if requested
    # Service name includes cacheName for potential multi-cache setups
    systemd.services."attic-login-${cfg.cacheName}" = mkIf cfg.autoLogin {
      description = "Log in to Attic cache ${cfg.cacheName}";
      wantedBy = [ "multi-user.target" ]; # Run on boot

      serviceConfig = {
        Type = "oneshot"; # Run once and exit
        RemainAfterExit = true; # Consider the service active after success
        User = "root"; # Push activation script runs as root, login needs matching user
        # Group = "root"; # Or dedicated group
        ExecStart = "${loginScript}";
      };
    };

    # 4. Systemd service to run 'attic watch-store' if requested
    systemd.services."attic-watch-store-${cfg.cacheName}" = mkIf cfg.watchStore.enable {
      description = "Attic Store Watcher for cache ${cfg.cacheName}";
      wantedBy = [ "multi-user.target" ]; # Start on boot

      # Dependencies: Wait for login service (if enabled) and network
      after = (optional cfg.autoLogin "attic-login-${cfg.cacheName}.service") ++ [
        "network-online.target"
      ];
      requires = optional cfg.autoLogin "attic-login-${cfg.cacheName}.service";
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple"; # Long-running process
        User = "root"; # Needs permissions to read store and push (uses login token)
        # Construct the command
        ExecStart = ''
          ${pkgs.attic-client}/bin/attic watch-store \
            --jobs ${toString cfg.watchStore.jobs} \
            ${escapeShellArg cfg.cacheName}
        '';
        Restart = "on-failure"; # Restart if the watcher crashes
        RestartSec = "10s"; # Wait 10 seconds before restarting
      };
    };

    # Optional: Optimize store for Attic (can slightly improve upload/download)
    # Consider adding this outside the module if you want it globally
    # nix.settings.auto-optimise-store = true;
  };
}
