{
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  ...
}:

with lib;

let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
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

  # Helper function to escape mount point path for systemd unit names
  escapeSystemdPath = path: builtins.replaceStrings [ "/" ] [ "-" ] (removePrefix "/" path);
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

    # Install JuiceFS mount helper
    system.activationScripts.juicefs-mount-helper = ''
      mkdir -p /run/wrappers/bin
      ln -sf ${cfg.package}/bin/juicefs /run/wrappers/bin/mount.juicefs
    '';

    # Create environment preparation services
    systemd.services = mapAttrs' (
      name: mountCfg:
      let
        # Generate names
        prepServiceName = "juicefs-env-${name}";
        mountUnitName = "mnt-${escapeSystemdPath (removePrefix "/mnt/" mountCfg.mountPoint)}.mount";
        envFilePath = "/run/juicefs-${name}.env";

        # Create preparation script
        prepScript = pkgs.writeShellScript prepServiceName ''
          #!/bin/sh
          set -e

          # Create environment file
          echo "# JuiceFS environment file for ${mountCfg.mountPoint}" > ${envFilePath}

          # Add credentials
          ${optionalString (mountCfg.metaPasswordFile != null) ''
            if [ -f "${mountCfg.metaPasswordFile}" ]; then
              echo "META_PASSWORD=$(cat ${mountCfg.metaPasswordFile})" >> ${envFilePath}
            fi
          ''}

          ${optionalString (mountCfg.rsaPassphraseFile != null) ''
            if [ -f "${mountCfg.rsaPassphraseFile}" ]; then
              echo "JFS_RSA_PASSPHRASE=$(cat ${mountCfg.rsaPassphraseFile})" >> ${envFilePath}
            fi
          ''}

          ${optionalString (mountCfg.region != null) ''
            echo "MINIO_REGION=${mountCfg.region}" >> ${envFilePath}
          ''}

          # Set permissions
          chmod 600 ${envFilePath}

          # Clean up any stale mounts before proceeding
          # if ! stat "${mountCfg.mountPoint}" 2>/dev/null; then
          #   echo "Cleaning up stale mount at ${mountCfg.mountPoint}"
          #   ${pkgs.util-linux}/bin/umount -lf ${mountCfg.mountPoint} 2>/dev/null || true
          #   ${pkgs.fuse}/bin/fusermount -uz ${mountCfg.mountPoint} 2>/dev/null || true
          #   rm -rf ${mountCfg.mountPoint} 2>/dev/null || true
          # fi

          # Ensure mount point exists
          mkdir -p ${mountCfg.mountPoint}
        '';
      in
      nameValuePair prepServiceName {
        description = "Prepare JuiceFS environment file for ${mountCfg.mountPoint}";
        before = [ mountUnitName ];
        wantedBy = [ mountUnitName ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${prepScript}";
        };
      }
    ) (filterAttrs (_: mountCfg: mountCfg.enable) cfg.mounts);

    # Create systemd mount units for each JuiceFS mount
    systemd.mounts = mapAttrsToList (
      name: mountCfg:
      let
        envFilePath = "/run/juicefs-${name}.env";
      in
      lib.mkIf mountCfg.enable {
        what = mountCfg.metaUrl;
        where = mountCfg.mountPoint;
        type = "juicefs";

        # Build mount options
        options =
          "_netdev,max-uploads=${toString mountCfg.maxUploads}"
          + ",buffer-size=${toString mountCfg.bufferSize}"
          + ",cache-dir=${mountCfg.cacheDir}"
          + optionalString mountCfg.writeback ",writeback"
          + optionalString mountCfg.readOnly ",ro"
          + concatStringsSep "" (mapAttrsToList (k: v: ",${k}=${v}") mountCfg.extraOptions);

        wantedBy = [ "multi-user.target" ];
        requires = [
          "juicefs-env-${name}.service"
          "network-online.target"
        ];
        after = [
          "juicefs-env-${name}.service"
          "network-online.target"
        ];

        # Systemd mount unit config
        unitConfig = {
          Description = "JuiceFS Mount for ${mountCfg.mountPoint}";
          DefaultDependencies = "no";
        };

        # Mount-specific config
        mountConfig = {
          # Add the environment file
          EnvironmentFile = envFilePath;
        };
      }
    ) cfg.mounts;
  };
}
