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
  cfg = config.${namespace}.networking.tailscale;
in
{
  options.${namespace}.networking.tailscale = with types; {
    enable = mkBoolOpt false "Whether or not to enable tailscale";
  };

  config = mkIf cfg.enable {

    # Enable tailscale.
    services = {
      tailscale = {
        enable = true;
        useRoutingFeatures = "client";
      };

    };
  };

}
