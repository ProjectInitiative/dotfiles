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

      programs.firefox = {
        enable = true;
        profiles = {
          id = 0;
          name = "default";
          isDefault = true;
          settings = {
            
          };

          search = {
            force = true;
            default = "duckduckgo";
            order = [ "duckduckgo" "google" ];
          };

          extensions = with pkgs.nur.repos.rycee.firefox-addons; [
            bitwarden
            darkreader
            greasemonkey
            tampermonkey
            sponsorblock
            tree-style-tab
            ublock-origin
            return-youtube-dislike
            youtube-popout-player
          ];

          
        };
      };

    };
  };
}
