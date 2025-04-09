{
  options,
  config,
  lib,
  pkgs,
  # namespace, # No longer needed for helpers
  ...
}:
with lib;
# with lib.${namespace}; # Removed custom helpers
let
  # Assuming 'namespace' is still defined in the evaluation scope for config path
  cfg = config.${namespace}.suites.bcachefs-utils;
in
{
  options.${namespace}.suites.bcachefs-utils = {
    enable = mkEnableOption "common bcachefs utilities suite."; # Use standard mkEnableOption
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      bcachefs-tools
      pkgs.bcachefs-doctor # Assuming package name doesn't include namespace
      pkgs.bcachefs-fua-test # Assuming package name doesn't include namespace
      pkgs.bcachefs-io-metrics # Assuming package name doesn't include namespace
    ];

  };
}
