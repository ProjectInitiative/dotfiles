{
  options,
  config,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.suites.backup;
  isGraphical = config.${namespace}.isGraphical;
in
{
  options.${namespace}.suites.backup = with types; {
    enable = mkBoolOpt false "Whether or not to enable digital-creation suite";
  };

  config = mkIf cfg.enable {
    home = {
      packages = with pkgs; [
        borgbackup
        backintime
        (mkIf isGraphical backintime-qt)
      ];
    };
  };

  # config = mkIf cfg.enable (mkMerge [
  #   (mkIf isGraphical {
  #     home = {
  #       packages = with pkgs; [
  #         bambu-studio
  #         gimp
  #         freecad
  #         libreoffice
  #         vlc
  #       ];
  #     };
  #   })
  # ]);

}
