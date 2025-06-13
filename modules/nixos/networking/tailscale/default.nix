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

  # This logic to select the correct key based on the ephemeral flag remains unchanged.
  tailscale_key =
    if cfg.ephemeral then
      config.sops.secrets.tailscale_ephemeral_auth_key.path
    else
      config.sops.secrets.tailscale_auth_key.path;
in
{
  # ===============================================================
  # Your options block is untouched. No changes needed here.
  # ===============================================================
  options.${namespace}.networking.tailscale = with types; {
    enable = mkBoolOpt false "Whether or not to enable tailscale";
    ephemeral = mkBoolOpt true "Use ephemeral node key for tailscale";
    extraArgs = mkOpt (listOf str) [ ] "Additional arguments to pass to tailscale.";
  };


  # ===============================================================
  # The entire 'config' block is replaced.
  # It now configures the official nixpkgs module instead of
  # creating its own systemd service.
  # ===============================================================
  config = mkIf cfg.enable {
    services.tailscale = {
      # Enable the official tailscale daemon and autoconnect service
      enable = true;

      # Pass the path to your sops-nix secret, respecting your 'ephemeral' flag
      authKeyFile = tailscale_key;

      # Pass all of your existing 'extraArgs' to the one-time 'up' command.
      # This is the core of the pass-through logic.
      # extraUpFlags = cfg.extraArgs;

      # Set a sensible default required for subnet routing.
      # You can override this in your host config if needed, e.g.,
      # services.tailscale.useRoutingFeatures = "both";
      useRoutingFeatures = "server";
    };

    # --- IMPORTANT NOTE ---
    # The 'extraSetFlags' option from the official module is NOT used here.
    # This means that settings like '--advertise-routes' will only be applied
    # once during initial provisioning. For fully declarative updates to those
    # settings, you should plan to eventually migrate your configurations
    # to use 'services.tailscale.extraSetFlags' directly.
    extraSetFlags = cf.extraArgs;
  };
}
