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
  cfg = config.${namespace}.suites.messengers;
  # Assuming isGraphical is defined at the top level of osConfig
  isGraphical = osConfig.isGraphical or false;
in
{
  options.${namespace}.suites.messengers = {
    enable = mkEnableOption "messengers suite"; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {

    home = {
      packages =
        with pkgs;
        mkIf isGraphical [
          element-desktop
          signal-desktop
          telegram-desktop
          thunderbird
        ];
    };

  };

}
