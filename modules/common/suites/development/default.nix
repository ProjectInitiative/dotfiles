{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.suites.development;
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment; # NixOS always has environment option
  isHomeManager = options ? home; # Home Manager always has home option
in
{
  options.${namespace}.suites.development = with types; {
    enable = mkBoolOpt false "Whether or not to enable common development configuration.";
  };

  config = mkIf cfg.enable (
    {

    }

    // optionalAttrs (!isHomeManager) {
      # Enable zsh system-wide
      programs.zsh.enable = true;

      ${namespace} = {
        networking = {
          tailscale = enabled;
        };

        virtualization = {
          podman = enabled;
          docker = enabled;
        };

        system = {
          locale = enabled;
          fonts = enabled;
        };

      };
    }
    // optionalAttrs (isHomeManager) {
      ${namespace} = {
        tools = {
          git = {
            enable = true;
            userEmail = "6314611+ProjectInitiative@users.noreply.github.com";
          };
          direnv = enabled;
          k8s = enabled;
          ansible = enabled;
        };
        security = {
          gpg = enabled;
        };
      };
      home = {
        packages = with pkgs; [
          go
          juicefs
          packer
          podman-compose
          python3
          python3Packages.pip
          rustup
        ];
      };
    }
  );
}
