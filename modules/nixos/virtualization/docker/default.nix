{
  options,
  config,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.virtualization.docker;
  # Extract the keys (user names) from snowfallorg.users
  users = builtins.attrNames config.snowfallorg.users;
in
{
  options.${namespace}.virtualization.docker = with types; {
    enable = mkBoolOpt false "Whether or not to enable docker";
  };

  config = mkIf cfg.enable {

    # Enable containers
    virtualisation = {
      docker = {
        enable = true;
      };
    };
    users.extraGroups.docker.members = users;

  };

}
