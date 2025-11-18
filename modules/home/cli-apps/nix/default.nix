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
  cfg = config.${namespace}.cli-apps.nix;

  # POSIX-compliant shell function for bash and zsh
  rebuildHostFunction = ''
    # Rebuilds and switches a remote NixOS host, piping output to nom.
    # Usage: rebuild-host <hostname>
    rebuild-host() {
      if [ -z "$1" ]; then
        echo "Error: Target hostname is required."
        echo "Usage: rebuild-host <hostname>"
        return 1
      fi
      export TARGET="$1"
      # The |& operator pipes both stdout and stderr
      nixos-rebuild --target-host "$TARGET" --use-remote-sudo --flake ".#$TARGET" switch --log-format internal-json |& nom --json
    }
  '';

  # Fish-specific shell function
  rebuildHostFunctionFish = ''
    # Rebuilds and switches a remote NixOS host, piping output to nom.
    # Usage: rebuild-host <hostname>
    function rebuild-host
      if test -z "$argv[1]"
        echo "Error: Target hostname is required."
        echo "Usage: rebuild-host <hostname>"
        return 1
      end
      set -gx TARGET $argv[1]
      # The |& operator pipes both stdout and stderr
      nixos-rebuild --target-host "$TARGET" --sudo --flake ".#$TARGET" switch --log-format internal-json |& nom --json
    end
  '';

in
{
  options.${namespace}.cli-apps.nix = with types; {
    enable = mkBoolOpt false "Whether or not to enable common nix utilities.";
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [
        deploy-rs
        nixos-anywhere
        nixfmt-rfc-style
        nix-prefetch-git
        nix-prefetch-github
        nix-search-cli
        nh
        nix-output-monitor # nom
        nvd
        sqlite
        hydra-check
      ];

      sessionVariables = {
        # Set the default flake path for nh (nix-helper)
        NH_FLAKE = "${config.${namespace}.user.home}/dotfiles";
      };

      shellAliases = {
        # nix-output-monitor (nom) wrappers
        nb = "nom build";
        ns = "nom shell";
        nd = "nom develop";
        nom-build = "nom build";
        nom-shell = "nom shell";

        # Alias for the rebuild-host function
        rebuild = "rebuild-host";
      };
    };

    # Add the rebuild-host function for Zsh
    programs.zsh.initContent = mkIf config.programs.zsh.enable rebuildHostFunction;

    # Add the rebuild-host function for Bash
    programs.bash.initExtra = mkIf config.programs.bash.enable rebuildHostFunction;

    # Add the rebuild-host function for Fish
    programs.fish.shellInit = mkIf config.programs.fish.enable rebuildHostFunctionFish;
  };
}
