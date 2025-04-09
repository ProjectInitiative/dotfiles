{
  options,
  config,
  pkgs,
  lib,
  # namespace, # No longer needed for helpers
  osConfig, # Assume osConfig is passed
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.suites.digital-creation;
  # Assuming isGraphical is defined at the top level of osConfig
  isGraphical = osConfig.isGraphical or false;
in
{
  options.${namespace}.suites.digital-creation = {
    enable = mkEnableOption "digital-creation suite"; # Use standard mkEnableOption
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
