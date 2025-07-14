# /etc/nixos/modules/bcachefs-options.nix
{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;
with lib.${namespace};
with lib.types;

let
  cfg = config.${namespace}.services.bcachefsFileOptions;

  
  # Use systemd-escape utility at build time
  escapeSystemdPath = path: 
    builtins.readFile (pkgs.runCommand "escape-path-${builtins.hashString "sha256" path}" {} ''
      echo -n "$(${pkgs.systemd}/bin/systemd-escape --path '${path}')" > $out
    '');
  # Helper to convert an attrset of options into command-line flags
  optionsToString = optionsSet:
    concatStringsSep " " (
      mapAttrsToList (name: value: "--${name}=${toString value}") optionsSet
    );

in
{
  options.${namespace}.services.bcachefsFileOptions = {
    enable = mkEnableOption (mdDoc "bcachefs scheduled file option setting service");

    jobs = mkOption {
      type = attrsOf (submodule {
        options = {
          enable = mkEnableOption (mdDoc "this specific file option job") // {
            default = true;
          };

          path = mkOption {
            type = types.str;
            description = mdDoc "The absolute path to the directory to apply options to.";
            example = "/mnt/pool/k8s/nvme-cache";
          };

          onCalendar = mkOption {
            type = types.str;
            default = "daily";
            description = mdDoc "Systemd OnCalendar expression for when to run this job.";
            example = "*-*-* 04:00:00";
          };

          fileOptions = mkOption {
            type = attrsOf (oneOf [ str int bool ]);
            description = mdDoc "An attribute set of bcachefs file options to apply.";
            example = literalExpression ''
              {
                background_target = "cache";
                promote_target = "cache";
              }
            '';
          };
        };
      });
      default = { };
      description = mdDoc "Configuration for multiple bcachefs file option jobs.";
    };
  };

  config = mkIf cfg.enable {
    systemd = {
      services = mapAttrs' (jobName: jobCfg: nameValuePair "bcachefs-file-options-${jobName}" {
        description = "Apply bcachefs options to ${jobCfg.path}";
        after = [ "local-fs.target" ];
        
        path = [ pkgs.bcachefs-tools ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart =
            let
              optionsString = optionsToString jobCfg.fileOptions;
            in
            ''
              ${pkgs.bcachefs-tools}/bin/bcachefs set-file-option ${optionsString} ${jobCfg.path}
            '';
        };
      }) (filterAttrs (name: job: job.enable) cfg.jobs);

      timers = mapAttrs' (jobName: jobCfg: nameValuePair "bcachefs-file-options-${jobName}" {
        description = "Timer for applying bcachefs options to ${jobCfg.path}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = jobCfg.onCalendar;
          Persistent = true;
          Unit = "bcachefs-file-options-${jobName}.service";
        };
      }) (filterAttrs (name: job: job.enable) cfg.jobs);
    };
  };
  }
