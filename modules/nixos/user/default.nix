{
  options,
  config,
  pkgs,
  lib,
  # namespace, # No longer needed for helpers
  inputs,
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.user;
  sops = config.sops;
  # Assuming defaultIcon is defined elsewhere or needs to be pkgs.null
  defaultIcon = null; # Placeholder, adjust if needed

in
{
  options.${namespace}.user = with types; {
    name = mkOption { type = types.str; default = "kylepzak"; description = "The name to use for the user account."; }; # Use standard mkOption
    fullName = mkOption { type = types.str; default = "Kyle Petryszak"; description = "The full name of the user."; }; # Use standard mkOption
    email = mkOption { type = types.str; default = "6314611+ProjectInitiative@users.noreply.github.com"; description = "The email of the user."; }; # Use standard mkOption
    # initialPassword = mkOption { type = types.str; default = "password"; description = "The initial password to use when the user is first created."; };
    icon = mkOption { type = types.nullOr types.package; default = defaultIcon; description = "The profile picture to use for the user."; }; # Use standard mkOption
    prompt-init = mkEnableOption "initial message when opening a new shell" // { default = true; }; # Use standard mkEnableOption, default true
    extraGroups = mkOption { type = types.listOf types.str; default = [ ]; description = "Groups for the user to be assigned."; }; # Use standard mkOption
    extraOptions = mkOption { type = types.attrs; default = { }; description = mdDoc "Extra options passed to `users.users.<name>`."; }; # Use standard mkOption
    authorized-keys = mkOption { type = types.listOf types.path; default = [ "${inputs.ssh-pub-keys}" ]; description = "Authorized SSH keys for user."; }; # Use standard mkOption
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
