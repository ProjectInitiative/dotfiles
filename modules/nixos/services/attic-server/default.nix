# ./modules/attic-server.nix (Simplified)
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
  cfg = config.${namespace}.services.attic.server;
in
{
  # Use the namespace in the options path
  options.${namespace}.services.attic.server = {
    enable = mkEnableOption "Attic daemon (atticd) service";

    user = mkOption {
      type = types.str;
      default = "atticd";
      description = "User account under which atticd runs.";
    };

    group = mkOption {
      type = types.str;
      default = "atticd";
      description = "Group account under which atticd runs.";
    };

    # --- Simplified Secret Management ---
    environmentFile = mkOption {
      type = types.path; # Module only cares about the path
      default = "/etc/atticd.env";
      description = ''
        Absolute path to the environment file containing secrets like ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64.
        *** The user is responsible for creating and managing this file ***
        (e.g., using sops-nix configured separately, manual creation, etc.)
        and ensuring it has the correct content (e.g., 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="YOUR_SECRET"')
        and permissions allowing the atticd user (${cfg.user}) to read it.
        Recommended permissions: 0400 owned by root, or 0440 owned by root:${cfg.group}.
      '';
    };

    # --- Core Settings (mapped to services.atticd.settings) ---
    settings = {
      listenAddress = mkOption {
        type = types.str;
        default = "[::]";
        example = "0.0.0.0";
        description = "IP address for atticd to listen on. '[::]' listens on all IPv6 and IPv4 addresses.";
      };

      listenPort = mkOption {
        type = types.port;
        default = 8080;
        description = "Port for atticd to listen on.";
      };

      # Add other settings from the official module's `settings` block if needed

      chunking = mkOption {
        type = types.submodule {
          options = {
            narSizeThreshold = mkOption { type = types.int; default = 64 * 1024; description = "Minimum NAR size (bytes) to trigger chunking (0=disabled, 1=all)."; };
            minSize = mkOption { type = types.int; default = 16 * 1024; description = "Preferred minimum chunk size (bytes)."; };
            avgSize = mkOption { type = types.int; default = 64 * 1024; description = "Preferred average chunk size (bytes)."; };
            maxSize = mkOption { type = types.int; default = 256 * 1024; description = "Preferred maximum chunk size (bytes)."; };
          };
        };
        default = {}; # Use atticd defaults unless overridden
        description = "Data chunking parameters. Changing these can impact deduplication.";
      };
    };

    # --- Storage (mapped to services.atticd.storage) ---
    storage = mkOption {
     type = types.submodule {
       options = {
         type = mkOption {
           type = types.enum [ "local" "s3" ]; # Enforce valid types
           default = "local"; # Default to local storage
           description = "Storage backend type ('local' or 's3').";
         };

         path = mkOption {
           type = types.path;
           default = "/var/cache/attic";
           # Description could mention this is primarily for 'local' type
           description = "Directory path where local cache data will be stored (used when type is 'local').";
         };

         # TODO: Add options for S3 if needed (region, bucket, endpoint, etc.)
         # You might want to make 'path' apply only when type == "local" using mkIf
         # and add S3 options that apply only when type == "s3".
         # For now, this simple structure works for 'local'.
       };
     };
     default = {}; # The submodule's defaults ("local", "/var/cache/attic") will apply
     description = "Storage backend configuration for Attic.";
    };

    # --- Garbage Collection (mapped to services.atticd.garbageCollection) ---
    garbageCollection = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "Attic garbage collection";
          schedule = mkOption { type = types.str; default = "daily"; example = "weekly"; description = "How often to run garbage collection."; };
          keepSince = mkOption { type = types.nullOr types.str; default = "30d"; example = "90d"; description = "Keep artifacts referenced since this duration."; };
          keepGenerations = mkOption { type = types.nullOr types.int; default = null; example = 10; description = "Keep the N most recent generations per cache."; };
        };
      };
      default = { enable = true; };
      description = "Garbage collection settings.";
    };

    # --- Firewall & Directory Management ---
    # openFirewall = mkOption {
    #   type = types.bool;
    #   default = cfg.enable; # Default to true if the server is enabled
    #   description = "Whether to automatically open the firewall port for atticd.";
    # };

    manageStorageDir = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to automatically create the storage directory with correct permissions using systemd-tmpfiles.";
    };
  };

  # --- Configuration Logic ---
  config = mkIf cfg.enable {
    # Configure the official services.atticd module
    # TODO: use flake
    environment.systemPackages = [ pkgs.attic-client pkgs.attic-server ];

    services.atticd = {
      enable = true;
      user = cfg.user;
      group = cfg.group;

      # Point to the user-managed environment file
      environmentFile = cfg.environmentFile; # Directly use the path provided

      # Map settings
      settings = {
        listen = "${cfg.settings.listenAddress}:${toString cfg.settings.listenPort}";
        jwt = {}; # Required empty block as per docs
        chunking = {
          nar-size-threshold = cfg.settings.chunking.narSizeThreshold;
          min-size = cfg.settings.chunking.minSize;
          avg-size = cfg.settings.chunking.avgSize;
          max-size = cfg.settings.chunking.maxSize;
        };

        # Map GC config (assuming official module structure)
         garbage-collection = {
           # These are likely always required or have valid TOML defaults (bool/string)
           enable = cfg.garbageCollection.enable;
           schedule = cfg.garbageCollection.schedule;
         }
         # Conditionally add keep-since if it's not null
         // lib.mkIf (cfg.garbageCollection.keepSince != null) {
              # Use the TOML key name expected by atticd (likely kebab-case)
              keep-since = cfg.garbageCollection.keepSince;
            }
         # Conditionally add keep-generations if it's not null
         // lib.mkIf (cfg.garbageCollection.keepGenerations != null) {
              # Use the TOML key name expected by atticd (likely kebab-case)
              keep-generations = cfg.garbageCollection.keepGenerations;
            };

        # Map storage config (assuming official module structure)
        storage = {
         type = cfg.storage.type;
         path = cfg.storage.path;

         # TODO: Map other storage options if/when added (e.g., region, bucket for S3)
        };

      };

    };

    # Ensure storage directory exists with correct permissions if requested
    systemd.tmpfiles.rules = mkIf cfg.manageStorageDir [
      # Ensure permissions allow the atticd user/group access
      "d ${escapeShellArg cfg.storage.path} 0750 ${escapeShellArg cfg.user} ${escapeShellArg cfg.group} - -"
    ];

    # Conditionally open the firewall port if requested
    # networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.settings.listenPort ];

  };
}
