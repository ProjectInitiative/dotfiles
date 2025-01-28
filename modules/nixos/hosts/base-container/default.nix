{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.base-container;
in
{
  options.${namespace}.hosts.base-container = with types; {
    enable = mkBoolOpt false "Whether or not to enable the base lxc machine config.";
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
