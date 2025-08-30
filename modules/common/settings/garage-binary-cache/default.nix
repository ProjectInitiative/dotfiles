{ lib, config, pkgs, ... }:
{}

# let
#   cfg = config.services.garageBinaryCache;

#   # Internal helper: did the user enable private pull or push?
#   needAwsCreds =
#     (cfg.pull.enable && cfg.pull.mode == "private") || cfg.push.enable;

#   # Construct substituter URL for pullers
#   pullSubstituter =
#     if cfg.pull.mode == "public"
#     then cfg.cache.websiteUrl
#     else "${cfg.cache.s3Url}&profile=${cfg.pull.aws.profileName}";
# in
# {
#   ###### OPTIONS ######
#   options.services.garageBinaryCache = {
#     enable = lib.mkEnableOption "Garage-backed Nix binary cache (pull/push)";

#     cache.websiteUrl = lib.mkOption {
#       type = lib.types.str;
#       example = "https://nix.example.com";
#       description = "Website endpoint used by public pullers.";
#     };

#     cache.s3Url = lib.mkOption {
#       type = lib.types.str;
#       default = "s3://nix?endpoint=garage.example.com&region=garage";
#       example = "s3://nix?endpoint=garage.example.com&region=garage";
#       description = "S3 URL for Garage (used by pushers and private pullers).";
#     };

#     publicKey = lib.mkOption {
#       type = lib.types.str;
#       example = "nix.example.com:eTGL6kvaQn6cDR/F9lDYUIP9nCVR/kkshYfLDJf1yKs=";
#       description = "Trusted public key for the cache.";
#     };

#     # ----- Pullers -----
#     pull.enable = lib.mkOption {
#       type = lib.types.bool;
#       default = true;
#       description = "Enable this host as a consumer (pull from the cache).";
#     };

#     pull.mode = lib.mkOption {
#       type = lib.types.enum [ "public" "private" ];
#       default = "public";
#       description = ''
#         Pull mode:
#         - "public": use website URL (anonymous reads).
#         - "private": use S3 URL requiring AWS creds (from sops).
#       '';
#     };

#     pull.aws.profileName = lib.mkOption {
#       type = lib.types.str;
#       default = "garage-cache-pull";
#       description = "AWS profile name used for private pulls.";
#     };

#     pull.aws.region = lib.mkOption {
#       type = lib.types.str;
#       default = "garage";
#       description = "Region written into the AWS config for private pulls.";
#     };

#     pull.aws.accessKeySecret = lib.mkOption {
#       type = lib.types.str;
#       default = "";
#       description = "Name of sops-nix secret containing the AWS access key for private pulls.";
#     };

#     pull.aws.secretKeySecret = lib.mkOption {
#       type = lib.types.str;
#       default = "";
#       description = "Name of sops-nix secret containing the AWS secret key for private pulls.";
#     };

#     # ----- Pushers -----
#     push.enable = lib.mkOption {
#       type = lib.types.bool;
#       default = false;
#       description = "Enable this host as a producer (auto-push builds to Garage).";
#     };

#     push.signingKeySecret = lib.mkOption {
#       type = lib.types.str;
#       default = "";
#       description = "Name of sops-nix secret containing the Nix cache private key PEM.";
#     };

#     push.aws.profileName = lib.mkOption {
#       type = lib.types.str;
#       default = "garage-cache-push";
#       description = "AWS profile name used by the uploader service.";
#     };

#     push.aws.region = lib.mkOption {
#       type = lib.types.str;
#       default = "garage";
#       description = "Region written into the AWS config for pushes.";
#     };

#     push.aws.accessKeySecret = lib.mkOption {
#       type = lib.types.str;
#       default = "";
#       description = "Name of sops-nix secret containing the AWS access key for pushes.";
#     };

#     push.aws.secretKeySecret = lib.mkOption {
#       type = lib.types.str;
#       default = "";
#       description = "Name of sops-nix secret containing the AWS secret key for pushes.";
#     };

#     # Advanced: tune the uploader
#     push.uploader.execExtraArgs = lib.mkOption {
#       type = lib.types.listOf lib.types.str;
#       default = [ ];
#       description = "Extra args passed to `nix copy` (e.g., --no-check-sigs).";
#     };

#     # File locations for AWS profiles (root daemon context)
#     awsPaths.credentials = lib.mkOption {
#       type = lib.types.path;
#       default = "/root/.aws/credentials";
#       description = "Where to write the rendered AWS credentials.";
#     };

#     awsPaths.config = lib.mkOption {
#       type = lib.types.path;
#       default = "/root/.aws/config";
#       description = "Where to write the rendered AWS config.";
#     };
#   };

#   ###### CONFIG ######
#   config = lib.mkIf cfg.enable {

#     # ---------- Consumers: nix.conf ----------
#     nix.settings = lib.mkMerge [
#       (lib.mkIf cfg.pull.enable {
#         substituters = [
#           "https://cache.nixos.org"
#           pullSubstituter
#         ];
#         trusted-public-keys = [
#           "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
#           cfg.publicKey
#         ];
#       })

#       # Producers also need to sign at build time
#       (lib.mkIf cfg.push.enable {
#         # Insert the private signing key installed by sops-nix (see below)
#         secret-key-files = [
#           (config.sops.secrets.${cfg.push.signingKeySecret}.path)
#         ];
#       })
#     ];

#     # ---------- Private pulls & pushes need AWS creds ----------
#     # We render AWS profiles via sops *templates* (not plain secrets),
#     # so we can combine multiple profiles into a single credentials file.
#     #
#     # Requires you to have sops-nix enabled at the system level.
#     assertions = [
#       {
#         assertion = !(needAwsCreds && (config.sops == null));
#         message = "services.garageBinaryCache: sops-nix must be enabled when using private pulls or push.";
#       }
#       {
#         assertion = !(cfg.push.enable && cfg.push.signingKeySecret == "");
#         message = "services.garageBinaryCache.push.signingKeySecret is required when push.enable = true.";
#       }
#       {
#         assertion =
#           !(cfg.pull.enable && cfg.pull.mode == "private" &&
#           (cfg.pull.aws.accessKeySecret == "" || cfg.pull.aws.secretKeySecret == ""));
#         message = "Private pulls require pull.aws.accessKeySecret and pull.aws.secretKeySecret.";
#       }
#       {
#         assertion =
#           !(cfg.push.enable &&
#           (cfg.push.aws.accessKeySecret == "" || cfg.push.aws.secretKeySecret == ""));
#         message = "Push requires push.aws.accessKeySecret and push.aws.secretKeySecret.";
#       }
#     ];

#     # Ensure parent dir for /root/.aws exists
#     systemd.tmpfiles.rules = lib.mkIf needAwsCreds [
#       "d /root/.aws 0700 root root -"
#     ];

#     # Signing key (private) for pushers: managed by sops-nix (owner root, 0400)
#     # You define it in your host's sops file; this just references it.
#     sops.secrets = lib.mkMerge [
#       (lib.mkIf cfg.push.enable {
#         "${cfg.push.signingKeySecret}" = { owner = "root"; mode = "0400"; };
#       })
#       (lib.mkIf (cfg.pull.enable && cfg.pull.mode == "private") {
#         "${cfg.pull.aws.accessKeySecret}" = { owner = "root"; mode = "0400"; };
#         "${cfg.pull.aws.secretKeySecret}" = { owner = "root"; mode = "0400"; };
#       })
#       (lib.mkIf cfg.push.enable {
#         "${cfg.push.aws.accessKeySecret}" = { owner = "root"; mode = "0400"; };
#         "${cfg.push.aws.secretKeySecret}" = { owner = "root"; mode = "0400"; };
#       })
#     ];

#     # Render AWS credentials (both profiles if enabled on same host)
#     sops.templates."aws-credentials" = lib.mkIf needAwsCreds {
#       # NOTE: placeholders read secret contents at render-time
#       content = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
#         (lib.optionalString (cfg.pull.enable && cfg.pull.mode == "private") ''
#           [${cfg.pull.aws.profileName}]
#           aws_access_key_id=${config.sops.placeholder.${cfg.pull.aws.accessKeySecret}}
#           aws_secret_access_key=${config.sops.placeholder.${cfg.pull.aws.secretKeySecret}}
#         '')
#         (lib.optionalString cfg.push.enable ''
#           [${cfg.push.aws.profileName}]
#           aws_access_key_id=${config.sops.placeholder.${cfg.push.aws.accessKeySecret}}
#           aws_secret_access_key=${config.sops.placeholder.${cfg.push.aws.secretKeySecret}}
#         '')
#       ]) + "\n";
#       owner = "root";
#       group = "root";
#       mode = "0600";
#       # write directly to target path
#       path = cfg.awsPaths.credentials;
#     };

#     sops.templates."aws-config" = lib.mkIf needAwsCreds {
#       content = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
#         (lib.optionalString (cfg.pull.enable && cfg.pull.mode == "private") ''
#           [profile ${cfg.pull.aws.profileName}]
#           region = ${cfg.pull.aws.region}
#         '')
#         (lib.optionalString cfg.push.enable ''
#           [profile ${cfg.push.aws.profileName}]
#           region = ${cfg.push.aws.region}
#         '')
#       ]) + "\n";
#       owner = "root";
#       group = "root";
#       mode = "0600";
#       path = cfg.awsPaths.config;
#     };

#     # ---------- Push uploader service (systemd) ----------
#     systemd.services.garage-binary-cache-uploader = lib.mkIf cfg.push.enable {
#       description = "Auto-upload new Nix store paths to Garage (S3)";

#       wantedBy = [ "multi-user.target" ];
#       after = [ "network-online.target" "nix-daemon.service" ];
#       requires = [ "nix-daemon.service" ];

#       # Ensure AWS files rendered before starting
#       requiresMountsFor = lib.mkIf needAwsCreds [ (builtins.dirOf cfg.awsPaths.credentials) ];
#       # Restart on failure; nix store monitor is a long-running stream
#       serviceConfig = {
#         Type = "simple";
#         Restart = "always";
#         RestartSec = 2;

#         # Ensure root sees ~/.aws/* (we wrote them to /root/.aws)
#         Environment = lib.optionals needAwsCreds [
#           "HOME=/root"
#         ];

#         # Script: monitor the store and push items as they appear
#         ExecStart = pkgs.writeShellScript "garage-cache-watch" ''
#           set -euo pipefail

#           # Stream JSON events of completed builds:
#           # each line like {"operation":"add","path":"/nix/store/..."}
#           ${pkgs.nix}/bin/nix store monitor --json | \
#           while IFS= read -r line; do
#             path=$(${pkgs.jq}/bin/jq -r '.path // empty' <<<"$line") || true
#             if [ -n "''${path:-}" ] && [ -e "$path" ]; then
#               echo "[garage-binary-cache] Uploading $path"
#               ${pkgs.nix}/bin/nix copy "$path" \
#                 --to '${cfg.cache.s3Url}&profile=${cfg.push.aws.profileName}' \
#                 ${lib.concatStringsSep " " (map lib.escapeShellArg cfg.push.uploader.execExtraArgs)}
#             fi
#           done
#         '';
#       };
#     };
#   };
# }

