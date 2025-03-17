{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;

let
  cfg = config.${namespace}.services.juicefs;

  mountOpts = {
    options = {
      enable = mkEnableOption "JuiceFS mount point";

      mountPoint = mkOption {
        type = types.str;
        description = "Path where the JuiceFS volume should be mounted";
        example = "/mnt/jfs/files";
      };

      metaUrl = mkOption {
        type = types.str;
        description = "Redis URL for JuiceFS metadata";
        example = "redis://127.0.0.1:6380/1";
      };

      metaPasswordFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to the secret containing the Redis password";
        example = "/run/secrets/redis_password";
      };

      rsaPassphraseFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to the secret containing the RSA passphrase";
        example = "/run/secrets/jfs_rsa_passphrase";
      };

      cacheDir = mkOption {
        type = types.str;
        default = "/var/jfsCache";
        description = "Directory paths of local cache";
      };

      region = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Region for object storage";
        example = "us-east-1";
      };

      writeback = mkOption {
        type = types.bool;
        default = false;
        description = "Upload objects in background";
      };

      background = mkOption {
        type = types.bool;
        default = true;
        description = "Run in background";
      };

      readOnly = mkOption {
        type = types.bool;
        default = false;
        description = "Allow lookup/read operations only";
      };

      maxUploads = mkOption {
        type = types.int;
        default = 20;
        description = "Number of connections to upload";
      };

      bufferSize = mkOption {
        type = types.int;
        default = 300;
        description = "Total read/write buffering in MB";
      };

      extraOptions = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Additional JuiceFS mount options";
        example = {
          "backup-meta" = "3600";
          "heartbeat" = "12";
        };
      };
    };
  };
in
{
  options.${namespace}.services.juicefs = {
    enable = mkEnableOption "JuiceFS service";

    package = mkOption {
      type = types.package;
      default = pkgs.juicefs;
      description = "JuiceFS package to use";
    };

    mounts = mkOption {
      type = types.attrsOf (types.submodule mountOpts);
      default = { };
      description = "JuiceFS mount configurations";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.services = mapAttrs' (
      name: mountCfg:
      nameValuePair "juicefs-mount-${name}" {
        description = "JuiceFS Mount for ${mountCfg.mountPoint}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        path = [ cfg.package ];

        script =
          let
            # Build the mount command with options
            metaPasswordEnv = optionalString (
              mountCfg.metaPasswordFile != null
            ) "META_PASSWORD=$(cat ${mountCfg.metaPasswordFile}) ";

            rsaPassphraseEnv = optionalString (
              mountCfg.rsaPassphraseFile != null
            ) "JFS_RSA_PASSPHRASE=$(cat ${mountCfg.rsaPassphraseFile}) ";

            regionEnv = optionalString (mountCfg.region != null) "MINIO_REGION=${mountCfg.region} ";

            backgroundFlag = optionalString mountCfg.background "--background ";
            writebackFlag = optionalString mountCfg.writeback "--writeback ";
            readOnlyFlag = optionalString mountCfg.readOnly "--read-only ";

            # Convert attrset to command line arguments
            extraOptsString = concatStringsSep " " (
              mapAttrsToList (name: value: "--${name} ${toString value}") mountCfg.extraOptions
            );
          in
          ''
            # Create mount point if it doesn't exist
            mkdir -p ${mountCfg.mountPoint}

            # Execute JuiceFS mount command
            ${metaPasswordEnv}${rsaPassphraseEnv}${regionEnv} \
            juicefs mount \
              ${backgroundFlag} \
              ${writebackFlag} \
              ${readOnlyFlag} \
              --max-uploads ${toString mountCfg.maxUploads} \
              --buffer-size ${toString mountCfg.bufferSize} \
              --cache-dir ${mountCfg.cacheDir} \
              ${extraOptsString} \
              ${mountCfg.metaUrl} ${mountCfg.mountPoint}
          '';

        serviceConfig = {
          Type = "forking";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      }
    ) (filterAttrs (_: mountCfg: mountCfg.enable) cfg.mounts);
  };
}
