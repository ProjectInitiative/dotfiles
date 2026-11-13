# {
#   lib,
#   osConfig ? { },
#   namespace,
#   ...
# }:
# {
#   home.stateVersion = lib.mkDefault (osConfig.system.stateVersion or "24.11");
# }

{
  lib,
  pkgs,
  osConfig,
  config,
  options,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  # inherit (lib) mkIf;
  # inherit (lib.${namespace}) mkStrOpt mkBoolOpt enabled;
  # inherit (lib.snowfall.system) is-darwin;
  is-linux = pkgs.stdenv.isLinux;
  is-darwin = pkgs.stdenv.isDarwin;

  cfg = config.${namespace}.home;
  # `or` fallback for standalone-HM contexts (containers) where the
  # snowfallorg option tree doesn't exist.
  username = config.snowfallorg.user.name or "kylepzak";
in
{
  options.${namespace}.home = {
    enable = mkBoolOpt false "Whether or not enable home configuration.";
    home = mkOpt types.str (
      if is-darwin then "/Users/${username}" else "/home/${username}"
    ) "The home directory of the user.";
  };

  config = mkIf cfg.enable {
    programs.home-manager = enabled;

    home = {
      inherit username;

      homeDirectory = cfg.home;
      # osConfig is null in non-NixOS contexts (standalone HM, containers);
      # the container policy module sets stateVersion explicitly.
      stateVersion = mkIf (osConfig != null) osConfig.system.stateVersion;
    };
  };
}
