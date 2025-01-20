{
  options,
  config,
  pkgs,
  lib,
  inputs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  # cfg = config.${namespace}.home;
in
{
  # options.${namespace}.home = with types; {
  #   file = mkOpt attrs { } (mdDoc "A set of files to be managed by home-manager's `home.file`.");
  #   configFile = mkOpt attrs { } (
  #     mdDoc "A set of files to be managed by home-manager's `xdg.configFile`."
  #   );
  #   extraOptions = mkOpt attrs { } "Options to pass directly to home-manager.";
  #   authorized-keys = mkOpt (listOf path) [ ] "Authorized SSH keys for user.";
  # };

  # config = {
  #   projectinitiative.home.extraOptions = {
  #     home.stateVersion = config.system.stateVersion;
  #     home.file = mkAliasDefinitions options.${namespace}.home.file;
  #     # xdg.enable = true;
  #     # xdg.configFile = mkAliasDefinitions options.${namespace}.home.configFile;
  #     openssh.authorizedkeys.keyfiles = cfg.authorized-keys;
  #   };

  #   snowfallorg.users.${config.${namespace}.user.name}.home.config =
  #     config.${namespace}.home.extraOptions;

  #   home-manager = {
  #     useUserPackages = true;
  #     useGlobalPkgs = true;
  #   };
  # };
}
