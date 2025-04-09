{
  options,
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.tools.ansible;
in
{
  options.${namespace}.tools.ansible = {
    enable = mkEnableOption "ansible."; # Use standard mkEnableOption
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
