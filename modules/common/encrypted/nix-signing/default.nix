{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment; # NixOS always has environment option
  isHomeManager = options ? home; # Home Manager always has home option

  cfg = config.${namespace}.encrypted.nix-signing;
  sops = config.sops;
  # Check if the key exists in sops
  # hasSigningKey = config.sops.secrets.nix-signing-key or null != null;
in {
  options.${namespace}.encrypted.nix-signing = with types; {
    enable = mkBoolOpt false "Nix binary cache signing";
    
    # keyFile = mkOption {
    #   type = types.str;
    #   default = "/run/secrets/nix-signing-key";
    #   description = "Path to the nix signing key provided by sops";
    # };
    
    # publicKey = mkOption {
    #   type = types.str;
    #   default = "shipyard:r+QK20NgKO/RisjxQ8rtxctsc5kQfY5DFCgGqvbmNYc=";
    #   description = "The public key for verifying signatures";
    # };
  };

  config = mkIf cfg.enable {

    # Only enable signing-related features when explicitly enabled
    # Register the key with SOPS only when needed
    sops.secrets = mkMerge [
      {
        nix-signing-key = {
          sopsFile = ./secrets.enc.yaml;
        };
      }
    ];

    # sops.secrets.nix-signing-key = {
    #   sopsFile = config.sops.defaultSopsFile;
    #   owner = "root";
    #   group = "root";
    #   mode = "0400";
    # };
    
    # Configure signing only when the key is available
    nix.settings = {
      # Set the secret key
      secret-key-files = [ sops.secrets.nix-signing-key.path ];
      
      # Auto-sign built derivations
      sign-builds = true;
    };
    
    ## TODO make this work on multiple system types
    # # Systems with the private key get some extra utilities
    # environment.systemPackages = [
    #   (pkgs.writeScriptBin "ensure-signed-paths" ''
    #     #!${pkgs.runtimeShell}
        
    #     # This script ensures that all paths in the current profile are signed
    #     # Useful to run before deploying with deploy-rs
        
    #     PROFILE="$1"
    #     if [ -z "$PROFILE" ]; then
    #       echo "Usage: ensure-signed-paths <profile-path>"
    #       echo "Example: ensure-signed-paths /nix/var/nix/profiles/system"
    #       exit 1
    #     fi
        
    #     # Get all paths in the profile closure
    #     echo "Finding all paths in profile $PROFILE..."
    #     PATHS=$(${pkgs.nix}/bin/nix-store -qR "$PROFILE")
        
    #     # Check each path and sign if needed
    #     for path in $PATHS; do
    #       if ! ${pkgs.nix}/bin/nix store verify --no-contents --no-trust --recursive "$path" &>/dev/null; then
    #         echo "Signing: $path"
    #         ${pkgs.nix}/bin/nix store sign --key-file ${sops.secrets.nix-signing-key.path} "$path"
    #       fi
    #     done
        
    #     echo "All paths in $PROFILE are now signed."
    #   '')
    # ];
    
    # # Add a pre-build hook for deploy-rs to ensure everything gets signed
    # system.activationScripts.ensureSignedDeployPaths = {
    #   deps = ["setupSecrets"];
    #   text = ''
    #     # This ensures all paths in the current system profile are signed
    #     # which helps deploy-rs succeed when pushing to remote nodes
    #     if [ -f ${sops.secrets.nix-signing-key.path} ]; then
    #       echo "Ensuring all paths in current profile are signed..."
    #       ${pkgs.nix}/bin/nix store sign --key-file ${sops.secrets.nix-signing-key.path} -r /run/current-system
    #     fi
    #   '';
    # };
  };
}
