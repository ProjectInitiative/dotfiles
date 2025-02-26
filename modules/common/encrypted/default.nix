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
  user = config.${namespace}.user;

  nix-public-signing-key = "shipyard:r+QK20NgKO/RisjxQ8rtxctsc5kQfY5DFCgGqvbmNYc="; 

  sops = config.sops;
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment; # NixOS always has environment option
  isHomeManager = options ? home; # Home Manager always has home option

  home-directory =
    if user.name == null then
      null
    else if isDarwin then
      "/Users/${user.name}"
    else
      "/home/${user.name}";

  # Helper function to decrypt sops files before evaluation
  parseYAMLOrJSONRaw = lib.${namespace}.mkParseYAMLOrJSON pkgs;
  decryptSopsFile =
    file:
    let
      # Use the manual method for systems that might not have the runtime files available
      sensitiveNotSecretAgeKeys = "${inputs.sensitiveNotSecretAgeKeys}/keys.txt";
      
      # need to figure out the impurity aspect
      # Read the key file content directly
      # sensitiveNotSecretAgeKeysContent = builtins.readFile sops.secrets.sensitive_not_secret_age_key.path;
        # Create a file in the Nix store with this content
      # sensitiveNotSecretAgeKeys = pkgs.writeText "sensitiveNotSecretAgeKeysContent" sensitiveNotSecretAgeKeysContent;

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
      # Always trust the public key (snowfall-lib will expose this)
      nix.settings = {
        trusted-users = [ "@wheel" user.name ];
        trusted-public-keys = [ nix-public-signing-key ];
      };

      inherit sensitiveNotSecret;
      sops = {
        # age.keyFile = mkIf isHomeManager "${home-directory}/.config/sops/age/key.txt";
        age.sshKeyPaths = [
          # (mkIf isHomeManager "${home-directory}/.ssh/id_ed25519")
          (mkIf isNixOS "/etc/ssh/ssh_host_ed25519_key")
        ];
        defaultSopsFile = ./secrets/secrets.enc.yaml;
      };
    }

    # common config
    {
      sops.secrets = {
        # sensitive_not_secret_age_key = {
        #   # owner = user.name;
        # };
      };
    }

    # NixOS-specific configurations
    (mkIf isNixOS {
      sops.secrets = {
        tailscale_ephemeral_auth_key = { };
        tailscale_auth_key = { };
        root_password.neededForUsers = true;
        user_password.neededForUsers = true;
        sensitive_not_secret_age_key = {
          owner = user.name;
        };
      };
    })

    # Home Manager-specific configurations
    (mkIf isHomeManager {
      sops.secrets = {
        user_password = { };
        sensitive_not_secret_age_key = { };
      };
    })
  ];
}
