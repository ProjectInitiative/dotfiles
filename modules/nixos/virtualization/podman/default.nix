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
  cfg = config.${namespace}.virtualization.podman;
  # Extract the keys (user names) from snowfallorg.users
  users = builtins.attrNames config.snowfallorg.users;
in
{
  options.${namespace}.virtualization.podman = with types; {
    enable = mkBoolOpt false "Whether or not to enable podman";
  };

  config = mkIf cfg.enable {

    # Enable containers
    virtualisation = {
      podman = {
        enable = true;
        dockerCompat = false;
        defaultNetwork.settings.dns_enabled = true;
      };
    };

  };

}
