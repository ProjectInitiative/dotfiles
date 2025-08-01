{
  config,
  lib,
  namespace,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.${namespace}.services.bcachefs-fs-options;

  fsOptionEntries =
    fsUUID: fsOptions:
    let
      fsPath = "/sys/fs/bcachefs/${fsUUID}/options";
    in
    mapAttrsToList (name: value: ''
      if [[ "$(cat ${fsPath}/${name})" != "${toString value}" ]]; then
        echo "${toString value}" > ${fsPath}/${name}
      fi
    '') fsOptions;

  fsOptionsScript = pkgs.writeShellScript "bcachefs-fs-options-script" (
    concatStringsSep "
" (
      mapAttrsToList (
        fsUUID: fsOptions: concatStringsSep "
" (fsOptionEntries fsUUID fsOptions)
      ) cfg.settings
    )
  );
in
{
  options.${namespace}.services.bcachefs-fs-options = {
    settings = mkOption {
      type = types.attrsOf (types.attrsOf (types.either types.str types.int));
      default = { };
      description = ''
        Declaratively set bcachefs filesystem-level options.
        The top-level attribute name is the filesystem UUID.
        The nested attribute set contains the option name and value.
      '';
      example = literalExpression ''
        {
          "27cac550-3836-765c-d107-51d27ab4a6e1" = {
            foreground_target = "hdd";
            background_target = "ssd";
            promote_target = "ssd";
          };
        }
      '';
    };
  };

  config.systemd.services.bcachefs-fs-options = {
    description = "Apply bcachefs filesystem-level options";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${fsOptionsScript}";
    };
  };
}
