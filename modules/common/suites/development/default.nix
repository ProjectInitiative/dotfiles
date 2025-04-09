{
  options,
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  osConfig, # Assume osConfig is passed
  system,
  inputs,
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.suites.development;
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment; # NixOS always has environment option
  isHomeManager = options ? home; # Home Manager always has home option
  # Assuming isGraphical is defined at the top level of osConfig
  isGraphical = osConfig.isGraphical or false;
in
{
  options.${namespace}.suites.development = {
    enable = mkEnableOption "common development configuration."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable (
    {

    }

    // optionalAttrs (!isHomeManager) {

      ${namespace} = {
        networking = {
          tailscale.enable = true; # Use standard boolean
        };

        virtualization = {
          podman.enable = true; # Use standard boolean
          docker.enable = true; # Use standard boolean
        };

        system = {
          locale.enable = true; # Use standard boolean
          fonts.enable = true; # Use standard boolean
        };

      };
    }
    // optionalAttrs (isHomeManager) {
      ${namespace} = {
        tools = {
          git = {
            enable = true; # Standard boolean
            userEmail = "6314611+ProjectInitiative@users.noreply.github.com";
            signingKeyFormat = "openpgp";
            # TODO: Make this not hardcoded
            signingKey = osConfig.sops.secrets.kylepzak_ssh_key.path;
          };
          direnv.enable = true; # Use standard boolean
          k8s.enable = true; # Use standard boolean
          ansible.enable = true; # Use standard boolean
          aider.enable = true; # Use standard boolean
        };
        security = {
          gpg.enable = true; # Use standard boolean
        };
      };
      home = {
        packages =
          with pkgs;
          [
            go
            juicefs
            # packer
            podman-compose
            python3
            python3Packages.pip
            ventoy-full
            rustup
          ]
          ++ lib.optionals isGraphical [ inputs.claude-desktop.packages.${system}.claude-desktop-with-fhs ];
      };
    }
  );
}
