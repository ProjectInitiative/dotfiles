{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.system.logging;
in
{
  options.${namespace}.system.logging = {
    enable = mkBoolOpt false "Whether to enable system logging configuration.";
    ramLogging = mkBoolOpt false "Whether to enable RAM-based logging (volatile journald).";
    maxRetentionMemory = mkOpt types.str "64M" "Maximum memory to use for journald logs.";
  };

  config = mkIf cfg.enable {
    services.journald.extraConfig = mkIf cfg.ramLogging ''
      Storage=volatile
      RuntimeMaxUse=${cfg.maxRetentionMemory}
    '';
  };
}
