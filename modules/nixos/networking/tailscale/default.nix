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
    # regular DNS servers. Do this through resolved directly rather than a
    # .network file: networkd managing tailscale0 makes tailscaled report
    # that it cannot manage the link's DNS settings.
    services.resolved.enable = true;
    systemd.services.tailscale-dns = {
      description = "Configure Tailscale split DNS";
      wantedBy = [ "multi-user.target" ];
      partOf = [ "tailscaled.service" ];
      after = [
        "systemd-resolved.service"
        "tailscaled.service"
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        for attempt in $(seq 1 30); do
          if ${pkgs.iproute2}/bin/ip link show tailscale0 >/dev/null 2>&1; then
            ${pkgs.systemd}/bin/resolvectl dns tailscale0 100.100.100.100
            # The routing domain limits this resolver to the tailnet zone;
            # the bare domain also makes single-label names (for example
            # `dinghy`) expand to `dinghy.${cfg.tailnetDomain}`.
            ${pkgs.systemd}/bin/resolvectl domain tailscale0 '~${cfg.tailnetDomain}' '${cfg.tailnetDomain}'
            exit 0
          fi
          sleep 1
        done
        echo "tailscale0 did not appear; split DNS was not configured" >&2
        exit 1
      '';
    };

  };
}
