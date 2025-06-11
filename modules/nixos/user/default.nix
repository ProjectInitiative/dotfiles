{
  options,
  config,
  pkgs,
  lib,
  namespace,
  inputs,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.user;
  sops = config.sops;

in
{
  options.${namespace}.user = with types; {
    name = mkOpt str "kylepzak" "The name to use for the user account.";
    fullName = mkOpt str "Kyle Petryszak" "The full name of the user.";
    email = mkOpt str "6314611+ProjectInitiative@users.noreply.github.com" "The email of the user.";
    # initialPassword =
    #   mkOpt str "password"
    #     "The initial password to use when the user is first created.";
    icon = mkOpt (nullOr package) defaultIcon "The profile picture to use for the user.";
    prompt-init = mkBoolOpt true "Whether or not to show an initial message when opening a new shell.";
    extraGroups = mkOpt (listOf str) [ ] "Groups for the user to be assigned.";
    extraOptions = mkOpt attrs { } (mdDoc "Extra options passed to `users.users.<name>`.");
    authorized-keys = mkOpt (listOf path) [ "${inputs.ssh-pub-keys}" ] "Authorized SSH keys for user.";
  };

  config = {
    # projectinitiative.home = {
    #   file = {};

    #   extraOptions = {};
    # };

    programs.zsh.enable =
      mkIf config.home-manager.users.${cfg.name}.${namespace}.cli-apps.zsh.defaultUserShell
        true;

    # TODO: make this user specific?
    security.sudo.wheelNeedsPassword = false;
    security.sudo-rs.wheelNeedsPassword = false;

    users.users.${cfg.name} = {
      isNormalUser = true;

      inherit (cfg) name;
      # inherit (cfg) name initialPassword;

      home = "/home/${cfg.name}";
      group = "users";

      # maybe check home-manager config
      shell =
        mkIf config.home-manager.users.${cfg.name}.${namespace}.cli-apps.zsh.defaultUserShell
          pkgs.zsh;

      # openssh.authorizedKeys.keyFiles = ["${inputs.ssh-pub-keys}"];
      openssh.authorizedKeys.keyFiles = cfg.authorized-keys;
      # openssh.authorizedKeys.keyFiles = cfg.authorized-keys ++ [
      #   "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIDCXiqG+u+KlXDdEOtSqYCAxvORNMDcXUJ9gUvG7zO+ deployer"
      # ];

      hashedPasswordFile = sops.secrets.user_password.path;

      # Arbitrary user ID to use for the user. Since I only
      # have a single user on my machines this won't ever collide.
      # However, if you add multiple users you'll need to change this
      # so each user has their own unique uid (or leave it out for the
      # system to select).
      uid = 1000;
    };

  };
}
