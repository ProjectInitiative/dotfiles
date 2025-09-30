
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.projectinitiative.services.s3-sync;
  namespace = [ "projectinitiative" "services" "s3-sync" ];
in
{
  options.${namespace} = {
    enable = mkEnableOption "Enable S3 sync service";

    user = mkOption {
      type = types.str;
      default = "root";
      description = "User to run the S3 sync service as.";
    };

    group = mkOption {
      type = types.str;
      default = "root";
      description = "Group to run the S3 sync service as.";
    };

    syncDir = mkOption {
      type = types.str;
      default = "/mnt/pool/buckets";
      description = "Directory to sync S3 buckets to.";
    };

    s3Remote = mkOption {
      type = types.str;
      default = "s3";
      description = "The rclone remote name for S3.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.s3-sync = {
      description = "Sync S3 buckets to local storage";
      serviceConfig = {
        Type = "OneShot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = pkgs.writeScript "s3-sync-script" ''
          #!${pkgs.bash}/bin/bash
          set -euo pipefail

          buckets=$(${pkgs.rclone}/bin/rclone lsjson ${cfg.s3Remote}: | ${pkgs.jq}/bin/jq -r '.[].Path')

          for bucket in $buckets; do
            echo "Syncing s3://$bucket to ${cfg.syncDir}/$bucket"
            ${pkgs.rclone}/bin/rclone sync ${cfg.s3Remote}:$bucket ${cfg.syncDir}/$bucket
          done
        '';
      };
    };

    systemd.timers.s3-sync = {
      description = "Run S3 sync daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
      unit = "s3-sync.service";
    };

    environment.systemPackages = [
      pkgs.rclone
      pkgs.jq
    ];
  };
}
