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
  tailscale_flags = unique ([ "--accept-dns=false" ] ++ cfg.extraArgs);
in
{
  # ===============================================================
  # Your options block is untouched. No changes needed here.
  # ===============================================================
  options.${namespace}.networking.tailscale = with types; {
    enable = mkBoolOpt false "Whether or not to enable tailscale";
    ephemeral = mkBoolOpt true "Use ephemeral node key for tailscale";
    extraArgs = mkOpt (listOf str) [ ] "Additional arguments to pass to tailscale.";
    tailnetDomain =
      mkOpt str "taildeab2.ts.net"
        "Tailnet DNS domain to route to Tailscale's local resolver.";
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

      # Keep host DNS management in the host resolver. The local Quad100
      # resolver remains available for MagicDNS when accept-dns is disabled.
      extraUpFlags = tailscale_flags;

      # Set a sensible default required for subnet routing.
      # You can override this in your host config if needed, e.g.,
      # services.tailscale.useRoutingFeatures = "both";
      useRoutingFeatures = "server";

      # Apply the same setting on subsequent `tailscale set` invocations,
      # while retaining any host-specific flags.
      extraSetFlags = tailscale_flags;
    };

    # Configure split DNS without allowing Tailscale to replace the host's
    # regular DNS servers. systemd-networkd applies this whenever tailscale0
    # appears, including after tailscaled restarts.
    services.resolved.enable = true;
    systemd.network = {
      enable = true;
      networks."99-tailscale" = {
        matchConfig.Name = "tailscale0";
        networkConfig = {
          DNS = [ "100.100.100.100" ];
          Domains = [ "~${cfg.tailnetDomain}" ];
        };
      };
    };

  };
}
