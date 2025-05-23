{
  lib,
  config,
  pkgs,
  namespace,
  osConfig ? { },
  ...
}:
let
  inherit (lib)
    types
    mkIf
    mkDefault
    mkMerge
    ;
  inherit (lib.${namespace}) mkOpt;

  cfg = config.${namespace}.user;

  is-linux = pkgs.stdenv.isLinux;
  is-darwin = pkgs.stdenv.isDarwin;

  home-directory =
    if cfg.name == null then
      null
    else if is-darwin then
      "/Users/${cfg.name}"
    else
      "/home/${cfg.name}";
in
{
  options.${namespace}.user = {
    enable = mkOpt types.bool true "Whether to configure the user account.";
    name = mkOpt (types.nullOr types.str) (config.snowfallorg.user.name or "kylepzak"
    ) "The user account.";

    fullName = mkOpt types.str "Kyle Petryszak" "The full name of the user.";
    email =
      mkOpt types.str "6314611+ProjectInitiative@users.noreply.github.com"
        "The email of the user.";

    home = mkOpt (types.nullOr types.str) home-directory "The user's home directory.";
    authorized-keys = mkOpt (types.str) "" "Authorized SSH keys for user.";
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.name != null;
          message = "projectinitiative.user.name must be set";
        }
        {
          assertion = cfg.home != null;
          message = "projectinitiative.user.home must be set";
        }
      ];

      home = {
        username = mkDefault cfg.name;
        homeDirectory = mkDefault cfg.home;
        file = {
          ".ssh/authorized_keys".text = cfg.authorized-keys;
        };
      };

    }
  ]);
}
