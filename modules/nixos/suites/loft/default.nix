
# /modules/nixos/suites/loft/default.nix
{ config, lib, pkgs, namespace, inputs, ... }:

with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.suites.loft;
  sops = config.sops;

in
{
  # --- Suite Options ---
  options.${namespace}.suites.loft = {
    enable = mkBoolOpt false "Enable the Loft binary cache suite.";

    enableClient = mkBoolOpt false "Enable the Loft client configuration for this host.";
    enableServer = mkBoolOpt false "Enable the Loft server (uploader) configuration for this host.";

    settings = {
      s3 = {
        bucket = mkOpt types.str "nix-cache" "The name of the S3 bucket.";
        region = mkOpt types.str "us-east-1" "The AWS region of the bucket.";
        endpoint = mkOpt types.str "http://172.16.1.50:31292" "The S3 endpoint URL.";
      };

      publicKey = mkOpt types.str "nix-cache:S7lSpN8xTtMELxw2cBl9nq4hEv2nCSShIe1re3P/q/s=" "The public key for the binary cache.";
      signingKeyName = mkOpt types.str "nix-cache" "The name of the signing key.";

      # Secrets defined as placeholder paths, to be filled by sops
      pullerAccessKeyFile = mkOpt types.path "/run/secrets/loft-puller-access-key" "Path to the S3 access key for pulling.";
      pullerSecretKeyFile = mkOpt types.path "/run/secrets/loft-puller-secret-key" "Path to the S3 secret key for pulling.";
      pusherAccessKeyFile = mkOpt types.path "/run/secrets/loft-pusher-access-key" "Path to the S3 access key for pushing.";
      pusherSecretKeyFile = mkOpt types.path "/run/secrets/loft-pusher-secret-key" "Path to the S3 secret key for pushing.";
      signingKeyFile = mkOpt types.path "/run/secrets/loft-signing-key" "Path to the Nix private signing key.";
    };

    server = {
      debug = mkBoolOpt false "Enable debug logging for the Loft service.";
      uploadThreads = mkOpt types.int 12 "Number of parallel upload threads.";
      scanOnStartup = mkBoolOpt true "Scan existing store paths on startup.";
      compression = mkOpt (types.enum [ "zstd" "xz" ]) "zstd" "Compression algorithm to use.";
      skipSignedByKeys = mkOpt (types.listOf types.str) [
        "cache.nixos.org-1"
        "nix-community.cachix.org-1"
      ] "A list of trusted public keys whose signatures should be skipped.";
      pruning = {
        enable = mkBoolOpt false "Enable automatic pruning of old cache artifacts.";
        schedule = mkOpt types.str "00:00" "Cron-style schedule for pruning.";
        retentionDays = mkOpt types.int 30 "How long to retain artifacts.";
      };
    };
  };

  # --- Configuration Logic ---
  config = mkIf cfg.enable (mkMerge [
    {
      # Unified secrets definition to avoid conflicts.
      sops.secrets = {
        # Client-specific secrets for pulling.
        loft-puller-access-key = mkIf cfg.enableClient { sopsFile = ../../../common/encrypted/secrets/secrets.enc.yaml; };
        loft-puller-secret-key = mkIf cfg.enableClient { sopsFile = ../../../common/encrypted/secrets/secrets.enc.yaml; };

        # Pusher secrets, needed by server and by client (for credentials file).
        loft-pusher-access-key = mkIf (cfg.enableClient || cfg.enableServer) { sopsFile = ../../../common/encrypted/secrets/secrets.enc.yaml; };
        loft-pusher-secret-key = mkIf (cfg.enableClient || cfg.enableServer) { sopsFile = ../../../common/encrypted/secrets/secrets.enc.yaml; };

        # Server-specific secret for signing.
        loft-signing-key = mkIf cfg.enableServer { sopsFile = ../../../common/encrypted/secrets/secrets.enc.yaml; };
      };
    }

    # === Client Configuration ===
    (mkIf cfg.enableClient {
      # Generate the AWS credentials file from sops secrets
      sops.templates."loft-aws-credentials.ini" = {
        mode = "0440";
        content = ''
          [nix-cache-puller]
          aws_access_key_id = ${config.sops.placeholder."loft-puller-access-key"}
          aws_secret_access_key = ${config.sops.placeholder."loft-puller-secret-key"}
          [nix-cache-pusher]
          aws_access_key_id = ${config.sops.placeholder."loft-pusher-access-key"}
          aws_secret_access_key = ${config.sops.placeholder."loft-pusher-secret-key"}
        '';
      };

      # Configure Nix to use the S3 cache and credentials
      nix = {
        # Make credentials available to the nix daemon and user commands
        envVars = {
          AWS_SHARED_CREDENTIALS_FILE = config.sops.templates."loft-aws-credentials.ini".path;
        };
        settings = {
          # Add the S3 endpoint as a substituter, using the puller profile
          substituters = [
            "s3://${cfg.settings.s3.bucket}?region=${cfg.settings.s3.region}&endpoint=${cfg.settings.s3.endpoint}&profile=nix-cache-puller"
          ];
          trusted-public-keys = [
            cfg.settings.publicKey
          ];
        };
      };
    })

    # === Server Configuration ===
    (mkIf cfg.enableServer {
      # Configure the Loft service using the suite's options
      services.loft = {
        enable = true;
        package = inputs.loft.packages.${pkgs.system}.default;

        s3 = {
          bucket = cfg.settings.s3.bucket;
          region = cfg.settings.s3.region;
          endpoint = cfg.settings.s3.endpoint;
          accessKeyFile = config.sops.secrets.loft-pusher-access-key.path;
          secretKeyFile = config.sops.secrets.loft-pusher-secret-key.path;
        };

        signingKeyPath = config.sops.secrets.loft-signing-key.path;
        signingKeyName = cfg.settings.signingKeyName;
        skipSignedByKeys = cfg.server.skipSignedByKeys;

        debug = cfg.server.debug;
        uploadThreads = cfg.server.uploadThreads;
        scanOnStartup = cfg.server.scanOnStartup;
        compression = cfg.server.compression;

        pruning = {
          enable = cfg.server.pruning.enable;
          schedule = cfg.server.pruning.schedule;
          retentionDays = cfg.server.pruning.retentionDays;
        };
      };
    })
  ]);
}
