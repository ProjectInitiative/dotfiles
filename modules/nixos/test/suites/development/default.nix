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
  cfg = config.${namespace}.suites.development;
in
{
  # imports = importAllCommonModules ../modules/common;

  options.${namespace}.suites.development = with types; {
    enable = mkBoolOpt false "Whether or not to enable common development configuration.";
  };

  config = mkIf cfg.enable {
    ${namespace} = {
      system = {
        fonts = enabled;
      };

      tools = {
        k8s = enabled;
      };

    };
  };
}
