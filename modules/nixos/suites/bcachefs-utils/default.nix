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
  cfg = config.${namespace}.suites.bcachefs-utils;
in
{
  options.${namespace}.suites.bcachefs-utils = with types; {
    enable = mkBoolOpt false "Whether or not to enable common terminal-env configuration.";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
        bcachefs-tools
        namespace.bcachefs-fua-test
        namespace.bcachefs-io-metrics
    ];
    
  };
}
