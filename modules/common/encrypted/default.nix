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
  # isHomeManager = config ? "home-manager" || config ? "home";
  isNixOS = config ? environment;  # NixOS always has environment config
  isHomeManager = config ? home;   # Home Manager always has home config

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

  config = mkMerge [
    {
      inherit sensitiveNotSecret;
      sops = {
        # age.keyFile = mkIf isHomeManager "${home-directory}/.config/sops/age/key.txt";
        age.sshKeyPaths = [
          (mkIf isHomeManager "${home-directory}/.ssh/id_ed25519")
          (mkIf isNixOS "/etc/ssh/ssh_host_ed25519_key")
        ];
        defaultSopsFile = ./secrets/secrets.enc.yaml;
      };
    }

    # NixOS-specific configurations
    (mkIf isNixOS {
      sops.secrets = {
        tailscale_ephemeral_auth_key = {};
        tailscale_auth_key = {};
        root_password.neededForUsers = true;
        user_password.neededForUsers = true;
      };
    })

    # Home Manager-specific configurations
    (mkIf isHomeManager {
      sops.secrets.user_password = {};
    })
  ];
}
