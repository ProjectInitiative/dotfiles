{
  options,
  config,
  pkgs,
  lib,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.networking.tools;
in
{
  options.${namespace}.networking.tools = with types; {
    enable = mkBoolOpt false "Whether or not to enable networking tools";
  };

  config = mkIf cfg.enable {

    # Enable tools.
    programs = {
      mtr = {
        enable = true;
      };

    };
  };

}
