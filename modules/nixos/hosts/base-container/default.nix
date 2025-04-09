{
  options,
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  modulesPath,
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.hosts.base-container;
in
{
  options.${namespace}.hosts.base-container = {
    enable = mkEnableOption "the base lxc machine config."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {

    # Basic system configuration
    system.stateVersion = "23.11";

    networking.networkmanager.enable = true;

    # Add your other configuration options here
    services.openssh.enable = true;
    # users.users.root.password = "changeme"; # Remember to change this
    programs.zsh.enable = true;
  };
}
