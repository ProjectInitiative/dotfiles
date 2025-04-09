{
  options,
  config,
  pkgs,
  lib,
  # namespace, # No longer needed for helpers
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.tools.git;
  gpg = config.${namespace}.security.gpg;
  user = config.${namespace}.user;

in
{
  options.${namespace}.tools.git = with types; {
    enable = mkEnableOption "git installation and configuration."; # Use standard mkEnableOption
    userName = mkOption { type = types.str; default = user.fullName; description = "The name to configure git with."; }; # Use standard mkOption
    userEmail = mkOption { type = types.str; default = user.email; description = "The email to configure git with."; }; # Use standard mkOption
    signingKey = mkOption { type = types.str; default = "/run/secrets/kylepzak_ssh_key"; description = "The key ID to sign commits with. (for ssh, this is a path)"; }; # Use standard mkOption
    # signingKey = mkOption { type = types.str; default = "CAEB4185C226D76B"; description = "The key ID to sign commits with. (for ssh, this is a path)"; };
    signingKeyFormat = mkOption { type = types.enum [ "openpgp" "ssh" "x509" ]; default = "openpgp"; description = "The signing key format. Valid values are 'openpgp', 'ssh', and 'x509'."; }; # Use standard mkOption
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [
        git
        git-filter-repo
        gitleaks
        lazygit
        trufflehog
      ];
    };

    programs.git = {
      enable = true; # Standard boolean
      inherit (cfg) userName userEmail;
      lfs.enable = true; # Use standard boolean
      signing = {
        key = cfg.signingKey;
        # TODO: enable when supported
        # format = cfg.signingKeyFormat;
        signByDefault = mkIf gpg.enable true;
      };
      extraConfig = {
        # TODO: remove when above option supported
        user.signingKey = cfg.signingKey;
        gpg = {
          format = cfg.signingKeyFormat;
          # Automatically set the appropriate signer program based on format
          ${cfg.signingKeyFormat}.program =
            if cfg.signingKeyFormat == "openpgp" then
              "${pkgs.gnupg}/bin/gpg"
            else if cfg.signingKeyFormat == "ssh" then
              "${pkgs.openssh}/bin/ssh-keygen"
            else if cfg.signingKeyFormat == "x509" then
              "${pkgs.gnupg}/bin/gpgsm"
            else
              null;
        };
        init = {
          defaultBranch = "main";
        };
        pull = {
          rebase = true;
        };
        push = {
          autoSetupRemote = true;
        };
        core = {
          whitespace = "trailing-space,space-before-tab";
        };
        safe = {
          directory = "${user.home}/work/config/.git";
        };
      };
    };
  };
}
