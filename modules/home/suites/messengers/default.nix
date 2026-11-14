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
  cfg = config.${namespace}.suites.messengers;
  # null-guard for standalone-HM (container) contexts
  isGraphical = if osConfig != null then osConfig.${namespace}.isGraphical else false;
  # Slack and Signal ship x86_64 binaries only; guard so aarch64 hosts
  # (DGX Spark, Surface Laptop Ultra) evaluate.
  isX86 = pkgs.stdenv.hostPlatform.isx86_64;
in
{
  options.${namespace}.suites.messengers = with types; {
    enable = mkBoolOpt false "Whether or not to enable messengers suite";
  };

  config = mkIf cfg.enable {

    home = {
      packages =
        with pkgs;
        mkIf isGraphical (
          [
            element-desktop
            telegram-desktop
            thunderbird
          ]
          ++ optionals isX86 [
            signal-desktop
            slack
          ]
        );
    };

  };

}
