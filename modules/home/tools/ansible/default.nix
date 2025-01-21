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
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
        ansible
        ansible-lint
      ];

      shellAliases = {
        ap = "ansible-playbook";
      };
    };
  };
}
