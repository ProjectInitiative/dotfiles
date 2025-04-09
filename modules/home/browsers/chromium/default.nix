{
  options,
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  osConfig, # Assume osConfig is passed
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.browsers.chromium;
  # Assuming isGraphical is defined at the top level of osConfig
  isGraphical = osConfig.isGraphical or false;
in
{
  options.${namespace}.browsers.chromium = {
    enable = mkEnableOption "chromium browser"; # Use standard mkEnableOption
  };

  config = mkIf (cfg.enable && isGraphical) {

    home = {
      packages = with pkgs; [
        chromium
      ];

    };
  };
}
