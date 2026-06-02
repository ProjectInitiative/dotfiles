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
    # Rebuilds a remote NixOS host, piping output to nom.
    # Usage: rebuild-host [--target <ip>] <hostname> [switch|test|boot]
    rebuild-host() {
      local target=""
      local hostname=""
      local action="switch"

      while [ $# -gt 0 ]; do
        case "$1" in
          --target)
            if [ -z "$2" ]; then
              echo "Error: --target requires an argument."
              return 1
            fi
            target="$2"
            shift 2
            ;;
          *)
            if [ -z "$hostname" ]; then
              hostname="$1"
            else
              action="$1"
            fi
            shift
            ;;
        esac
      done

      if [ -z "$hostname" ]; then
        echo "Error: Target hostname is required."
        echo "Usage: rebuild-host [--target <ip>] <hostname> [switch|test|boot]"
        return 1
      fi

      nixos-rebuild --target-host "''${target:-$hostname}" --sudo --flake ".#$hostname" "$action" --log-format internal-json |& nom --json
    }
  '';

  # Fish-specific shell function
  rebuildHostFunctionFish = ''
    # Rebuilds a remote NixOS host, piping output to nom.
    # Usage: rebuild-host [--target <ip>] <hostname> [switch|test|boot]
    function rebuild-host
      set target ""
      set hostname ""
      set action "switch"

      set i 1
      while test $i -le (count $argv)
        switch $argv[$i]
          case --target
            set i (math $i + 1)
            if test $i -gt (count $argv)
              echo "Error: --target requires an argument."
              return 1
            end
            set target $argv[$i]
          case '*'
            if test -z "$hostname"
              set hostname $argv[$i]
            else
              set action $argv[$i]
            end
        end
        set i (math $i + 1)
      end

      if test -z "$hostname"
        echo "Error: Target hostname is required."
        echo "Usage: rebuild-host [--target <ip>] <hostname> [switch|test|boot]"
        return 1
      end

      if test -z "$target"
        set target $hostname
      end

      nixos-rebuild --target-host "$target" --sudo --flake ".#$hostname" "$action" --log-format internal-json |& nom --json
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
        nixfmt
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
