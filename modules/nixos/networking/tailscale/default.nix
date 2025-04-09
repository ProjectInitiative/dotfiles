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
  cfg = config.${namespace}.networking.tailscale;

  tailscale_key =
    if config.${namespace}.networking.tailscale.ephemeral then
      config.sops.secrets.tailscale_ephemeral_auth_key.path
    else
      config.sops.secrets.tailscale_auth_key.path;
in
{
  options.${namespace}.networking.tailscale = {
    enable = mkEnableOption "tailscale"; # Use standard mkEnableOption
    ephemeral = mkEnableOption "ephemeral node key for tailscale" // { default = true; }; # Use standard mkEnableOption, default true
    extraArgs = mkOption { type = types.listOf types.str; default = [ ]; description = "Additional arguments to pass to tailscale."; }; # Use standard mkOption
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
      script =
        let
          extraArgsString = if cfg.extraArgs != [ ] then builtins.concatStringsSep " " cfg.extraArgs else "";
        in
        ''
          tailscale up --auth-key "$(cat ${tailscale_key})" --reset ${extraArgsString}
        '';

    };

  };

}
