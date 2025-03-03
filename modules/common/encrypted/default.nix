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
      # If initial system activation does not drop the age key in /tmp/sensitive/sensitive-not-secret-age-key.txt and the build fails, copy the key from a working machine and it should work and setup systemd correctly for next time.

      decryptedFile =
        pkgs.runCommand "decrypt-sops"
          {
            nativeBuildInputs = [ pkgs.sops ];

            SOPS_AGE_KEY_FILE = sops.secrets.sensitive_not_secret_age_key.path;
            # not added to nix store because of /run
            sandbox-paths = [ sops.secrets.sensitive_not_secret_age_key.path ];
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

  config = (
    # common config
    {

      inherit sensitiveNotSecret;
      # this gets overriden when using // operator
      # sops = {
      #   # age.keyFile = mkIf isHomeManager "${home-directory}/.config/sops/age/key.txt";
      #   age.sshKeyPaths = [
      #     # (mkIf isHomeManager "${home-directory}/.ssh/id_ed25519")
      #     (mkIf isNixOS "/etc/ssh/ssh_host_ed25519_key")
      #   ];
      #   defaultSopsFile = ./secrets/secrets.enc.yaml;
      # };

      # nix.settings = {
      # THIS IS BREAKING BECAUSE IT IS OVERRIDING NIXOS CACHE FOR HOME_MANAGER
      #   trusted-public-keys = [ nix-public-signing-key ];
      #   # allow reading from /run/secrets/sensitive_not_secret_age_key
      #   allow-symlinked-store = true;
      #   # allow reading from /run/secrets/sensitive_not_secret_age_key and not putting in nix-store
      #   allowed-impure-host-deps = ["/run/secrets/sensitive_not_secret_age_key"];
      #   # allow-unsafe-native-code-during-evaluation = true;
      #   sandbox-paths = ["/run/secrets/sensitive_not_secret_age_key"];
      # };
    }

    # NixOS-specific configurations
    // optionalAttrs isNixOS (mkMerge [
      
      {
          sops = {
          defaultSopsFile = ./secrets/secrets.enc.yaml;
          age.sshKeyPaths = [
            "/etc/ssh/ssh_host_ed25519_key"
          ];
          secrets = {
            tailscale_ephemeral_auth_key = { };
            tailscale_auth_key = { };
            root_password.neededForUsers = true;
            user_password.neededForUsers = true;
            sensitive_not_secret_age_key = {
              group = "nixbld";
              # TESTING PURPOSES ONLY - so nix repl can read
              mode = "444";
            };
          };
        };
      }
      # Use mkMerge to create the above config, sops paths, before creating nix.settings
      # which uses sops secrets paths
      {

        nix.settings = {
          trusted-users = [
            "@wheel"
            user.name
          ];
          trusted-public-keys = [ nix-public-signing-key ];
          allow-symlinked-store = true;
          allowed-impure-host-deps = [ config.sops.secrets.sensitive_not_secret_age_key.path ];
          sandbox-paths = [ config.sops.secrets.sensitive_not_secret_age_key.path ];
          # allow-unsafe-native-code-during-evaluation = true;
        };
        inherit sensitiveNotSecret;

      }
    ])

    # Darwin-specific configurations
    // optionalAttrs (isDarwin && !isHomeManager) {
      # Other Darwin-specific configurations
      sops = {
        defaultSopsFile = ./secrets/secrets.enc.yaml;
        secrets = {
          sensitive_not_secret_age_key = { };
        };
      };
    }

    # Home Manager-specific configurations (both Darwin and Linux)
    # TODO this use case doesn't quite work yet. Specifically because home-manager's "lib" is not being passed (or accessible?) in this module.

    # // optionalAttrs isHomeManager {
    #   # For Home Manager, use home.activation to run the script
    #   home.activation.copySensitiveKey = lib.hm.dag.entryAfter ["writeBoundary"] ''
    #     $DRY_RUN_CMD ${copyKeyScript}
    #   '';

    #   # Other Home Manager-specific configurations
    #   sops = {
    #     defaultSopsFile = ./secrets/secrets.enc.yaml;
    #     age.sshKeyPaths = [
    #       # TODO: enable this once I get all user keys stored in repo
    #       # "${home-directory}/.ssh/id_ed25519"
    #       "/etc/ssh/ssh_host_ed25519_key"
    #       (mkIf isLinux "/etc/ssh/ssh_host_ed25519_key")
    #       (mkIf isDarwin "<Darwin-key-path>")
    #     ];
    #     secrets = {
    #       user_password = { };
    #       sensitive_not_secret_age_key = { };
    #     };
    #   };
    # }

  );
}
