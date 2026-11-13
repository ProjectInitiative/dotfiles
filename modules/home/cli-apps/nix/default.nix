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
    # Usage: rebuild-host [--target <ip>] [--arm] <hostname> [switch|test|boot]
    #   --arm  build ON the target host (BUILD_ARM_NATIVE=true + --impure) —
    #             for aarch64 hosts rebuilt from an aarch64 machine (DGX Spark,
    #             lightships) where the target builds its own closure natively.
    rebuild-host() {
      local target=""
      local hostname=""
      local action="switch"
      local arm=0

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
          --arm)
            arm=1
            shift
            ;;
          -*)
            echo "Error: unknown flag $1"
            echo "Usage: rebuild-host [--target <ip>] [--arm] <hostname> [switch|test|boot]"
            return 1
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
        echo "Usage: rebuild-host [--target <ip>] [--arm] <hostname> [switch|test|boot]"
        return 1
      fi

      if [ -z "$target" ]; then
        target="$hostname"
      fi

      local -a extra_flags=()
      local env_prefix=""
      if [ "$arm" -eq 1 ]; then
        env_prefix="BUILD_ARM_NATIVE=true"
        extra_flags=(--impure)
      fi

      env $env_prefix nixos-rebuild $extra_flags \
        --target-host "$target" --sudo --flake ".#$hostname" "$action" \
        --log-format internal-json |& nom --json
    }
  '';

  # Fish-specific shell function
  rebuildHostFunctionFish = ''
    # Rebuilds a remote NixOS host, piping output to nom.
    # Usage: rebuild-host [--target <ip>] [--arm] <hostname> [switch|test|boot]
    #   --arm  build ON the target host (BUILD_ARM_NATIVE=true + --impure) —
    #             for aarch64 hosts rebuilt from an aarch64 machine (DGX Spark,
    #             lightships) where the target builds its own closure natively.
    function rebuild-host
      set target ""
      set hostname ""
      set action "switch"
      set arm 0

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
          case --arm
            set arm 1
          case '-*'
            echo "Error: unknown flag $argv[$i]"
            echo "Usage: rebuild-host [--target <ip>] [--arm] <hostname> [switch|test|boot]"
            return 1
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
        echo "Usage: rebuild-host [--target <ip>] [--arm] <hostname> [switch|test|boot]"
        return 1
      end

      if test -z "$target"
        set target $hostname
      end

      set extra_flags
      set env_prefix ""
      if test "$arm" -eq 1
        set env_prefix "BUILD_ARM_NATIVE=true"
        set extra_flags --impure
      end

      env $env_prefix nixos-rebuild $extra_flags \
        --target-host "$target" --sudo --flake ".#$hostname" "$action" \
        --log-format internal-json |& nom --json
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
