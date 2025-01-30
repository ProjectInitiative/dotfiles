{
  options,
  config,
  lib,
  pkgs,
  namespace,
  inputs,
  ...
}:
with lib;
with lib.${namespace};
let
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

  # Helper function to decrypt sops files before evaluation
  decryptSopsFile =
    file:
    let
      sensitiveNotSecretAgeKeys = "${inputs.sensitiveNotSecretAgeKeys}/keys.txt";
      decryptedFile =
        pkgs.runCommand "decrypt-sops"
          {
            nativeBuildInputs = [ pkgs.sops ];
            SOPS_AGE_KEY_FILE = sensitiveNotSecretAgeKeys;
          }
          ''
            sops -d ${file} > $out
          '';
    in
    readYAMLOrJSONRaw (builtins.readFile decryptedFile);

  # Decrypt the sensitive SOPS file
  sensitiveNotSecret = decryptSopsFile ./sensitive/sensitive.enc.yaml;
in
{
  # Define options for sensitiveNotSecret
  options.sensitiveNotSecret = mkOption {
    type = types.attrs;
    description = "Decrypted sensitive but not secret configuration";
    default = { };
  };
  config = {
    inherit sensitiveNotSecret;

    sops = {
      age.keyFile = "${home-directory}/.config/sops/age/key.txt"; # must have no password!
      # It's also possible to use a ssh key, but only when it has no password:
      age.sshKeyPaths = [
        # location for user SSH keys
        "${home-directory}/.ssh/id_ed25519"
        # location for default server keys
        "/etc/ssh/ssh_host_ed25519"
      ];
      defaultSopsFile = ./secrets/secrets.enc.yaml;
      secrets = {
        tailscale_pre_auth = { };
        root_password = { };
        user_password = { };
      };
      # secrets.test = {
      #   # sopsFile = ./secrets.yml.enc; # optionally define per-secret files

      #   # %r gets replaced with a runtime directory, use %% to specify a '%'
      #   # sign. Runtime dir is $XDG_RUNTIME_DIR on linux and $(getconf
      #   # DARWIN_USER_TEMP_DIR) on darwin.
      #   path = "%r/test.txt";
      # };
    };
  };

}
