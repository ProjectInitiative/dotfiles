{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.tools.ansible;
in
{
  options.${namespace}.tools.ansible = with types; {
    enable = mkBoolOpt false "Whether or not to enable ansible.";
    lint = {
      enable = mkBoolOpt true "Whether or not to enable ansible-lint.";
    };
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        ansible
      ] ++ (
        if cfg.lint.enable then [ ansible-lint ] else [ ]
      );

      shellAliases = {
        ap = "ansible-playbook";
      };
    };
  };
}
