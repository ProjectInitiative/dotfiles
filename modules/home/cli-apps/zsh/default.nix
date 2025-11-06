{
  lib,
  config,
  pkgs,
  namespace,
  options,
  ...
}:
with lib;
with lib.${namespace};
let
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  isNixOS = options ? environment; # NixOS always has environment config
  isHomeManager = options ? home; # Home Manager always has home config
  inherit (lib) mkEnableOption mkIf;
  user = config.${namespace}.user;

  cfg = config.${namespace}.cli-apps.zsh;

  tty-color-support = with lib.${namespace}.colors; ''
    if [ "$TERM" = "linux" ]; then
      echo -ne "\e]P0${without-hash nord.nord0}" # black
      echo -ne "\e]P8${without-hash nord.nord3}" # darkgrey
      echo -ne "\e]P1${without-hash nord.nord11}" # darkred
      echo -ne "\e]P9${without-hash nord.nord11}" # red
      echo -ne "\e]P2${without-hash nord.nord14}" # darkgreen
      echo -ne "\e]PA${without-hash nord.nord14}" # green
      echo -ne "\e]P3${without-hash nord.nord12}" # brown
      echo -ne "\e]PB${without-hash nord.nord13}" # yellow
      echo -ne "\e]P4${without-hash nord.nord10}" # darkblue
      echo -ne "\e]PC${without-hash nord.nord10}" # blue
      echo -ne "\e]P5${without-hash nord.nord15}" # darkmagenta
      echo -ne "\e]PD${without-hash nord.nord15}" # magenta
      echo -ne "\e]P6${without-hash nord.nord8}" # darkcyan
      echo -ne "\e]PE${without-hash nord.nord8}" # cyan
      echo -ne "\e]P7${without-hash nord.nord5}" # lightgrey
      echo -ne "\e]PF${without-hash nord.nord6}" # white
      clear
    fi
  '';
in
{
  options.${namespace}.cli-apps.zsh = {
    enable = mkEnableOption "ZSH";
    defaultUserShell = mkBoolOpt true "Whether to set zsh as the default shell for the user";
  };

  config = mkIf cfg.enable (
    {
      programs = {

        zsh = {
          enable = true;
          enableCompletion = true;
          syntaxHighlighting.enable = true;
          autosuggestion.enable = true;
          oh-my-zsh = {
            enable = true;
            theme = "robbyrussell";
            plugins = [
              "git"
              "docker"
              "kubectl"
            ];
          };

          # interactiveShellInit = ''
          #   eval "$(${pkgs.atuin}/bin/atuin init zsh)"
          #   eval "$(zoxide init zsh)"
          #   export PATH="''${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
          # '';
          shellAliases = {
            # sudo = "sudo -E";
            mkdir = "mkdir -p";
            make = "make -j $(nproc)";
            tailscale-up = "sudo tailscale up --login-server https://ts.projectinitiative.io --accept-routes";
          };
        };
      };
    }
    # NixOS-specific configuration
    // lib.optionalAttrs isNixOS {
      users.users.${user} = lib.mkIf cfg.defaultUserShell {
        ${user}.shell = pkgs.zsh;
      };
      # users.users = lib.mkIf (cfg.defaultUserShell && cfg.userName != "") {
      #   ${cfg.userName}.shell = pkgs.zsh;
      # };
    }

    # Home Manager-specific configuration
    // lib.optionalAttrs isHomeManager {
      home.sessionVariables = lib.mkIf cfg.defaultUserShell {
        SHELL = "${pkgs.zsh}/bin/zsh";
        ET_NO_TELEMETRY = "1";
      };

      home.packages = with pkgs; [
      ];
    }
  );
}
