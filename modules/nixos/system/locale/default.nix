{
  options,
  config,
  pkgs,
  lib,
  # namespace, # No longer needed for helpers
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.system.locale;
in
{
  options.${namespace}.system.locale = {
    enable = mkEnableOption "locale settings management."; # Use standard mkEnableOption
    timezone = mkOption { type = types.str; default = "America/Chicago"; description = "Timezone you wish to use"; }; # Use standard mkOption
  };

  config = mkIf cfg.enable {
    console = {
      keyMap = mkForce "us";
    };
    # Set your time zone.
    time.timeZone = cfg.timezone;

    # Select internationalisation properties.
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };
}
