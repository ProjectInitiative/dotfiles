{
  options,
  config,
  lib,
  pkgs,
  namespace,
  osConfig ? { },
  system,
  inputs,
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
  isGraphical = osConfig.${namespace}.isGraphical;
in
{
  options.${namespace}.suites.development = with types; {
    enable = mkBoolOpt false "Whether or not to enable common development configuration.";
  };

  config = mkIf cfg.enable (
    {

    }

    // optionalAttrs (!isHomeManager) {

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

        services = {
          eternal-terminal = enabled;
        };

        suites = {
          attic = {
            enableClient = true;
          };
        };

      };
    }
    // optionalAttrs (isHomeManager) {
      ${namespace} = {
        tools = {
          git = {
            enable = true;
            userEmail = "6314611+ProjectInitiative@users.noreply.github.com";
            signingKeyFormat = "ssh";
            # TODO: Make this not hardcoded
            signingKey = "/home/kylepzak/.ssh/id_ed25519.pub";
          };
          direnv = enabled;
          k8s = enabled;
          ansible = enabled;
          aider = enabled;
        };
        security = {
          gpg = enabled;
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
            # ventoy-full - removed until https://github.com/ventoy/Ventoy/issues/3224 is resolved.
            rustup
          ]
          ++ lib.optionals isGraphical [ inputs.claude-desktop.packages.${system}.claude-desktop-with-fhs ];
      };
    }
  );
}
