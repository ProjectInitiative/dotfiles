{ lib, config, pkgs, ... }:

let
  cfg = config.services.s3BinaryCache;

  # Internal helper: did the user enable private pull or push?
  needAwsCreds =
    (cfg.pull.enable && cfg.pull.mode == "private") || cfg.push.enable;

  # Construct substituter URL for pullers
  pullSubstituter =
    if cfg.pull.mode == "public"
    then cfg.cache.websiteUrl
    else "${cfg.cache.s3Url}&profile=${cfg.pull.aws.profileName}";
in
{
  ###### OPTIONS ######
  options.services.s3BinaryCache = {
    enable = lib.mkEnableOption "S3-backed Nix binary cache (pull/push)";
    cache.websiteUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://nix.example.com";
      description = "Website endpoint used by public pullers (CloudFront, S3 website, etc).";
    };
    cache.s3Url = lib.mkOption {
      type = lib.types.str;
      default = "s3://nix-cache?region=us-east-1";
      example = lib.literalExpression ''
        # For AWS S3
        "s3://my-nix-cache-bucket?region=us-west-2"
        # For self-hosted S3 (e.g., MinIO)
        "s3://nix-cache?endpoint=http://10.0.0.5:9000&region=us-east-1"
      '';
      description = ''
        S3 URL for the cache bucket (used by pushers and private pullers).
        For S3-compatible services, use the `endpoint` parameter.
      '';
    };
    publicKey = lib.mkOption {
      type = lib.types.str;
      example = "nix.example.com:eTGL6kvaQn6cDR/F9lDYUIP9nCVR/kkshYfLDJf1yKs=";
      description = "Trusted public key for the cache.";
    };
    pull = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable this host as a consumer (pull from the cache).";
      };
      mode = lib.mkOption {
        type = lib.types.enum [ "public" "private" ];
        default = "public";
        description = ''
          Pull mode:
          - "public": use website URL (anonymous reads via CloudFront/S3 website).
          - "private": use S3 URL requiring AWS credentials (from sops).
        '';
      };
      aws = {
        profileName = lib.mkOption {
          type = lib.types.str;
          default = "s3-cache-pull";
          description = "AWS profile name used for private pulls.";
        };
        region = lib.mkOption {
          type = lib.types.str;
          default = "us-east-1";
          description = "AWS region for private pulls.";
        };
        accessKeySecret = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Name of the sops-nix secret for the AWS access key (private pulls).";
        };
        secretKeySecret = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Name of the sops-nix secret for the AWS secret key (private pulls).";
        };
      };
    };
    push = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable this host as a producer (auto-push builds to S3).";
      };
      signingKeySecret = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Name of the sops-nix secret containing the Nix cache private key.";
      };
      aws = {
        profileName = lib.mkOption {
          type = lib.types.str;
          default = "s3-cache-push";
          description = "AWS profile name used by the uploader service.";
        };
        region = lib.mkOption {
          type = lib.types.str;
          default = "us-east-1";
          description = "AWS region for pushes.";
        };
        accessKeySecret = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Name of the sops-nix secret for the AWS access key (pushes).";
        };
        secretKeySecret = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Name of the sops-nix secret for the AWS secret key (pushes).";
        };
      };
      uploader = {
        mode = lib.mkOption {
          type = lib.types.enum [ "auto" "periodic" "post-build-hook" ];
          default = "auto";
          description = ''
            Upload monitoring mode:
            - "auto": same as "periodic" (post-build-hook is recommended for real-time uploads)
            - "periodic": use periodic scanning every N seconds
            - "post-build-hook": configure via nix.settings.post-build-hook (disables this service)
          '';
        };
        periodicInterval = lib.mkOption {
          type = lib.types.int;
          default = 60;
          description = "Interval in seconds for periodic mode scanning.";
        };
        execExtraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra args passed to `nix copy` (e.g., --no-check-sigs).";
        };
      };
    };
    awsPaths = {
      credentials = lib.mkOption {
        type = lib.types.path;
        default = "/root/.aws/credentials";
        description = "Where to write the rendered AWS credentials.";
      };
      config = lib.mkOption {
        type = lib.types.path;
        default = "/root/.aws/config";
        description = "Where to write the rendered AWS config.";
      };
    };
  };

  ###### CONFIG ######
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = lib.optionals cfg.push.enable [
      "d /var/lib/s3-binary-cache 0755 root root -"
    ] ++ lib.optionals needAwsCreds [
      "d /root/.aws 0700 root root -"
    ];

    nix.settings = lib.mkMerge [
      (lib.mkIf cfg.pull.enable {
        substituters = [ "https://cache.nixos.org" pullSubstituter ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          cfg.publicKey
        ];
      })
      (lib.mkIf (cfg.push.enable && cfg.push.signingKeySecret != "") {
        secret-key-files = [ (config.sops.secrets.${cfg.push.signingKeySecret}.path) ];
      })
      (lib.mkIf (cfg.push.enable && cfg.push.uploader.mode == "post-build-hook") {
        post-build-hook = pkgs.writeShellScript "s3-cache-post-build-hook" ''
          set -euf
          if [ -z "$OUT_PATHS" ]; then
            exit 0
          fi
          export HOME=/root
          export AWS_CONFIG_FILE=${cfg.awsPaths.config}
          export AWS_SHARED_CREDENTIALS_FILE=${cfg.awsPaths.credentials}
          echo "Uploading paths to S3 cache: $OUT_PATHS" >&2
          exec ${pkgs.nix}/bin/nix copy --to '${cfg.cache.s3Url}&profile=${cfg.push.aws.profileName}' \
            ${lib.concatStringsSep " " (map lib.escapeShellArg cfg.push.uploader.execExtraArgs)} \
            $OUT_PATHS
        '';
      })
    ];

    assertions = [
      {
        assertion = !(needAwsCreds && (config.sops == null));
        message = "s3BinaryCache requires sops-nix to be enabled for private access.";
      }
      {
        assertion = !(cfg.push.enable && cfg.push.signingKeySecret == "");
        message = "push.signingKeySecret is required when push.enable = true.";
      }
      {
        assertion = !(cfg.pull.enable && cfg.pull.mode == "private" &&
          (cfg.pull.aws.accessKeySecret == "" || cfg.pull.aws.secretKeySecret == ""));
        message = "Private pulls require pull.aws.accessKeySecret and pull.aws.secretKeySecret.";
      }
      {
        assertion = !(cfg.push.enable &&
          (cfg.push.aws.accessKeySecret == "" || cfg.push.aws.secretKeySecret == ""));
        message = "Push requires push.aws.accessKeySecret and push.aws.secretKeySecret.";
      }
    ];

    sops.secrets = lib.mkMerge [
      (lib.mkIf (cfg.pull.enable && cfg.pull.mode == "private") {
        "${cfg.pull.aws.accessKeySecret}" = { owner = "root"; };
        "${cfg.pull.aws.secretKeySecret}" = { owner = "root"; };
      })
      (lib.mkIf cfg.push.enable {
        "${cfg.push.signingKeySecret}" = { owner = "root"; };
        "${cfg.push.aws.accessKeySecret}" = { owner = "root"; };
        "${cfg.push.aws.secretKeySecret}" = { owner = "root"; };
      })
    ];

    sops.templates."s3-cache-aws-credentials" = lib.mkIf needAwsCreds {
      content =
        (lib.optionalString (cfg.pull.enable && cfg.pull.mode == "private") ''
          [${cfg.pull.aws.profileName}]
          aws_access_key_id = ''${config.sops.placeholder."${cfg.pull.aws.accessKeySecret}"}
          aws_secret_access_key = ''${config.sops.placeholder."${cfg.pull.aws.secretKeySecret}"}
        '') +
        (lib.optionalString cfg.push.enable ''
          [${cfg.push.aws.profileName}]
          aws_access_key_id = ''${config.sops.placeholder."${cfg.push.aws.accessKeySecret}"}
          aws_secret_access_key = ''${config.sops.placeholder."${cfg.push.aws.secretKeySecret}"}
        '');
      owner = "root";
      mode = "0400";
      path = cfg.awsPaths.credentials;
    };

    sops.templates."s3-cache-aws-config" = lib.mkIf needAwsCreds {
      content =
        (lib.optionalString (cfg.pull.enable && cfg.pull.mode == "private") ''
          [profile ${cfg.pull.aws.profileName}]
          region = ${cfg.pull.aws.region}
        '') +
        (lib.optionalString cfg.push.enable ''
          [profile ${cfg.push.aws.profileName}]
          region = ${cfg.push.aws.region}
        '');
      owner = "root";
      mode = "0400";
      path = cfg.awsPaths.config;
    };

    systemd.services.s3-binary-cache-uploader = lib.mkIf (cfg.push.enable && cfg.push.uploader.mode != "post-build-hook") {
      description = "Auto-upload new Nix store paths to S3 binary cache";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "nix-daemon.service" ];
      requires = [ "nix-daemon.service" ];
      unitConfig = {
        RequiresMountsFor = [ (builtins.dirOf cfg.awsPaths.credentials) ];
      };
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 10;
        Environment = [
          "HOME=/root"
          "AWS_CONFIG_FILE=${cfg.awsPaths.config}"
          "AWS_SHARED_CREDENTIALS_FILE=${cfg.awsPaths.credentials}"
        ];
        ExecStart = pkgs.writeShellScript "s3-cache-watch" ''
          set -euo pipefail
          echo "[s3-binary-cache] Starting uploader..."
          echo "[s3-binary-cache] Target: ${cfg.cache.s3Url}&profile=${cfg.push.aws.profileName}"
          if command -v aws >/dev/null 2>&1; then
            if ! AWS_PROFILE=${cfg.push.aws.profileName} aws sts get-caller-identity >/dev/null 2>&1; then
              echo "[s3-binary-cache] WARNING: AWS credentials test failed, uploads may fail"
            fi
          else
            echo "[s3-binary-cache] AWS CLI not available, skipping credential test"
          fi
          use_monitor=false
          case "${cfg.push.uploader.mode}" in
            "auto")
              if ${pkgs.nix}/bin/nix store monitor --help >/dev/null 2>&1; then
                use_monitor=true
                echo "[s3-binary-cache] Auto-detected 'nix store monitor' support"
              else
                echo "[s3-binary-cache] 'nix store monitor' not available, using periodic mode"
              fi
              ;;
            "monitor")
              if ${pkgs.nix}/bin/nix store monitor --help >/dev/null 2>&1; then
                use_monitor=true
                echo "[s3-binary-cache] Forcing 'nix store monitor' mode"
              else
                echo "[s3-binary-cache] ERROR: 'nix store monitor' forced but not available" >&2
                exit 1
              fi
              ;;
            "periodic")
              echo "[s3-binary-cache] Forcing periodic mode"
              ;;
          esac
          if [ "$use_monitor" = "true" ]; then
            echo "[s3-binary-cache] Using 'nix store monitor' for real-time uploads"
            ${pkgs.nix}/bin/nix store monitor --json | \
            while IFS= read -r line; do
              path=$(${pkgs.jq}/bin/jq -r '.path // empty' <<<"$line") || continue
              if [ -n "''${path:-}" ] && [ -e "$path" ]; then
                echo "[s3-binary-cache] Uploading $path"
                if ${pkgs.nix}/bin/nix copy "$path" \
                  --to '${cfg.cache.s3Url}&profile=${cfg.push.aws.profileName}' \
                  ${lib.concatStringsSep " " (map lib.escapeShellArg cfg.push.uploader.execExtraArgs)}; then
                  echo "[s3-binary-cache] Successfully uploaded $path"
                else
                  echo "[s3-binary-cache] Failed to upload $path" >&2
                fi
              fi
            done
          else
            echo "[s3-binary-cache] Using periodic sync mode"
            echo "[s3-binary-cache] This will upload all new store paths every ${toString cfg.push.uploader.periodicInterval} seconds"
            uploaded_paths="/var/lib/s3-binary-cache/uploaded-paths"
            touch "$uploaded_paths"
            while true; do
              ${pkgs.nix}/bin/nix path-info --all | while read -r path; do
                if ! grep -Fxq "$path" "$uploaded_paths" 2>/dev/null; then
                  echo "[s3-binary-cache] Uploading new path: $path"
                  if ${pkgs.nix}/bin/nix copy "$path" \
                    --to '${cfg.cache.s3Url}&profile=${cfg.push.aws.profileName}' \
                    ${lib.concatStringsSep " " (map lib.escapeShellArg cfg.push.uploader.execExtraArgs)}; then
                    echo "[s3-binary-cache] Successfully uploaded $path"
                    echo "$path" >> "$uploaded_paths"
                  else
                    echo "[s3-binary-cache] Failed to upload $path (may already exist or error occurred)" >&2
                  fi
                fi
              done
              if [ $(wc -l < "$uploaded_paths") -gt 10000 ]; then
                tail -n 5000 "$uploaded_paths" > "$uploaded_paths.tmp"
                mv "$uploaded_paths.tmp" "$uploaded_paths"
              fi
              sleep ${toString cfg.push.uploader.periodicInterval}
            done
          fi
        '';
      };
    };
  };
}
