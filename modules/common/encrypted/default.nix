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

  sensitiveKeyTmpPath = "/tmp";
  sensitiveKeyFileName = "sensitive-not-secret-age-key.txt";
  sensitiveKeyPath = "${sensitiveKeyTmpPath}/${sensitiveKeyFileName}";
  

  # Helper function to decrypt sops files before evaluation
  parseYAMLOrJSONRaw = lib.${namespace}.mkParseYAMLOrJSON pkgs;
  decryptSopsFile =
    file:
    let
      # Use the manual method for systems that might not have the runtime files available
      # sensitiveNotSecretAgeKeys = "${inputs.sensitiveNotSecretAgeKeys}/keys.txt";
      
      # If initial system activation does not drop the age key in /tmp/sensitive-not-secret-age-key.txt and the build fails, copy the key from a working machine and it should work and setup systemd correctly for next time.
      
      # Read the key file content directly
      sensitiveNotSecretAgeKeysContent = builtins.readFile sensitiveKeyPath;
        # Create a file in the Nix store with this content
      sensitiveNotSecretAgeKeys = pkgs.writeText "sensitiveNotSecretAgeKeysContent" sensitiveNotSecretAgeKeysContent;


      decryptedFile =
        pkgs.runCommand "decrypt-sops"
          {
            nativeBuildInputs = [ pkgs.sops ];
            SOPS_AGE_KEY_FILE = sensitiveNotSecretAgeKeys;
            # not added to nix store because of /run
            # SOPS_AGE_KEY_FILE = sops.secrets.sensitive_not_secret_age_key.path;
          }
          ''
            echo $SOPS_AGE_KEY_FILE
            sops -d ${file} > $out
          '';
    in
    parseYAMLOrJSONRaw (builtins.readFile decryptedFile);

  # Decrypt the sensitive SOPS file
  sensitiveNotSecret = decryptSopsFile ./sensitive/sensitive.enc.yaml;

  sourceSecretPath = sops.secrets.sensitive_not_secret_age_key.path;

  # Script to copy the sensitive key
  copyKeyCommands = ''
    # Create directory if it doesn't exist
    mkdir -p ${sensitiveKeyTmpPath}
    
    if [ -f "${sourceSecretPath}" ]; then
      # Copy the key to the new location
      cp "${sourceSecretPath}" "${sensitiveKeyPath}"
      chmod 640 "${sensitiveKeyPath}"
      echo "Sensitive key copied to ${sensitiveKeyPath}"
    else
      echo "Source key at ${sourceSecretPath} not found"
    fi
  '';
  # Also keep the script version for other uses (like macOS)
  copyKeyScript = pkgs.writeShellScript "copy-sensitive-key" ''
    ${copyKeyCommands}
  '';
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
    }

    

    # NixOS-specific configurations
    // optionalAttrs isNixOS {

      nix.settings = {
        trusted-users = [ "@wheel" user.name ];
        trusted-public-keys = [ nix-public-signing-key ];
      };

      # Create the systemd service to copy the key
      systemd.services.copy-sensitive-key = {
        description = "Copy sensitive but not secret key to tmpfs";
        wantedBy = [ "multi-user.target" ];
        after = [ "sops-nix.service" ];
        before = [ "nix-daemon.service" ];
        script = copyKeyCommands;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };
      
      # Set up tmpfs for sensitive keys
      systemd.tmpfiles.rules = [
        "d ${sensitiveKeyTmpPath} 0750 root ${user.name} - -"
      ];

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
            owner = user.name;
          };
        };
      };
    }

    # Darwin-specific configurations
    // optionalAttrs (isDarwin && !isHomeManager) {
      # Use launchd to run the script on Darwin
      launchd.user.agents.copy-sensitive-key = {
        serviceConfig = {
          Label = "user.copy-sensitive-key";
          ProgramArguments = [ "${pkgs.bash}/bin/bash" "-c" "${copyKeyScript}" ];
          RunAtLoad = true;
          KeepAlive = false;
          StandardOutPath = "/tmp/copy-sensitive-key.log";
          StandardErrorPath = "/tmp/copy-sensitive-key.error.log";
        };
      };
      
      # Other Darwin-specific configurations
      sops = {
        defaultSopsFile = ./secrets/secrets.enc.yaml;
        secrets = {
          sensitive_not_secret_age_key = {};
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

