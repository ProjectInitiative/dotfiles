{
  options,
  config,
  pkgs,
  lib,
  namespace,
  osConfig ? { },
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.suites.digital-creation;
  isGraphical = lib.attrByPath [ namespace "isGraphical" ] false osConfig;
in
{
  options.${namespace}.suites.digital-creation = with types; {
    enable = mkBoolOpt false "Whether or not to enable digital-creation suite";
  };

  config = mkIf (cfg.enable && isGraphical) {
    home = {
      packages = with pkgs; [
        bambu-studio
        gimp
        inkscape
        freecad
        libreoffice
        vlc
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
