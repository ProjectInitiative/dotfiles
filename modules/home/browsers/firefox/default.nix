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
  cfg = config.${namespace}.browsers.firefox;
in
{
  options.${namespace}.browsers.firefox = with types; {
    enable = mkBoolOpt false "Whether or not to enable firefox browser";
  };

  config = mkIf cfg.enable {

    home = {
      packages = with pkgs; [
      ];

      # PROGRAMS.FIREFOX = {
      #   ENABLE = TRUE;
      #   PROFILES = {
      #     ID = 0;
      #     NAME = "DEFAULT";
      #     ISDEFAULT = TRUE;
      #     SETTINGS = {
            
      #     };

      #     SEARCH = {
      #       FORCE = TRUE;
      #       DEFAULT = "DUCKDUCKGO";
      #       ORDER = [ "DUCKDUCKGO" "GOOGLE" ];
      #     };

      #     EXTENSIONS = WITH PKGS.NUR.REPOS.RYCEE.FIREFOX-ADDONS; [
      #       BITWARDEN
      #       DARKREADER
      #       BYPASS-PAYWALLS-CLEAN
      #       GREASEMONKEY
      #       TAMPERMONKEY
      #       SPONSORBLOCK
      #       TREE-STYLE-TAB
      #       UBLOCK-ORIGIN
      #       RETURN-YOUTUBE-DISLIKE
      #       YOUTUBE-POPOUT-PLAYER
      #     ];

          
      #   };
      # };

    };
  };
}
