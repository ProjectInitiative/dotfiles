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
  cfg = config.${namespace}.tools.git;
  gpg = config.${namespace}.security.gpg;
  user = config.${namespace}.user;

in
{
  options.${namespace}.tools.git = with types; {
    enable = mkBoolOpt false "Whether or not to install and configure git.";
    userName = mkOpt types.str user.fullName "The name to configure git with.";
    userEmail = mkOpt types.str user.email "The email to configure git with.";
    signingKey =
      mkOpt types.str "/run/secrets/kylepzak_ssh_key"
        "The key ID to sign commits with. (for ssh, this is a path)";
    # signingKey = mkOpt types.str "CAEB4185C226D76B" "The key ID to sign commits with. (for ssh, this is a path)";
    signingKeyFormat = mkOpt (types.enum [
      "openpgp"
      "ssh"
      "x509"
    ]) "openpgp" "The signing key format. Valid values are 'openpgp', 'ssh', and 'x509'.";
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
      enable = true;
      inherit (cfg) userName userEmail;
      lfs = enabled;
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
