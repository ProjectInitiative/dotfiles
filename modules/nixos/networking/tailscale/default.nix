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

    systemd.services.tailscale-up = {
      description = "Pre-seed tailscale";
      path = [
        pkgs.tailscale
      ];

      # Start after basic system services are up
      after = [
        "tailscaled.service"
        # "network.target"
        # "multi-user.target"
      ];

      # Don't consider boot failed if this service fails
      wantedBy = [ "multi-user.target" ];

      # Service configuration
      serviceConfig = {
        # Type = "";
        # RemainAfterExit = true;
        # ExecStartPre = "";
      };

      # The actual tailscale script
      script = ''
        tailscale up --auth-key "$(cat${config.sops.secrets.tailscale_auth_key.path})" --reset
      '';

      # Clean up on service stop
      preStop = ''
        tailscale down
      '';
    };

  };

}
