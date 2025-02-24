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

  sops = config.sops;
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment;  # NixOS always has environment option
  isHomeManager = options ? home;   # Home Manager always has home option

  home-directory =
    if cfg.name == null then
      null
    else if isDarwin then
      "/Users/${cfg.name}"
    else
      "/home/${cfg.name}";

  # Helper function to decrypt sops files before evaluation
  parseYAMLOrJSONRaw = lib.${namespace}.mkParseYAMLOrJSON pkgs;
  decryptSopsFile =
    file:
    let
      sensitiveNotSecretAgeKeys = "${inputs.sensitiveNotSecretAgeKeys}/keys.txt";
      # sensitiveNotSecretAgeKeys = sops.secrets.sensitive_not_secret_age_key.path;

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
    parseYAMLOrJSONRaw (builtins.readFile decryptedFile);

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

    # common config
    {
      sops.secrets = {
        sensitive_not_secret_age_key = {};
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
