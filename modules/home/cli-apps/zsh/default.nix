{
  lib,
  config,
  pkgs,
  namespace,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;

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
  };

  config = mkIf cfg.enable {
    programs = {

      zsh = {
        enable = true;
        enableCompletion = true;
        syntaxHighlighting.enable = true;
        # interactiveShellInit = ''
        #   eval "$(${pkgs.atuin}/bin/atuin init zsh)"
        #   eval "$(zoxide init zsh)"
        #   export PATH="''${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
        # '';
        shellAliases = {
          make = "make -j $(nproc)";
          tailscale-up = "sudo tailscale up --login-server https://ts.projectinitiative.io --accept-routes";
        };
      };

    };
  };
}

