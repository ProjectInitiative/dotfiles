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
  # Do not let tailscaled change the host resolver. The separate service below
  # only points split-DNS traffic at Quad100 and listens for Tailscale state
  # changes through the local API event stream.
  # Drop host-level accept-dns overrides so this module's policy cannot be
  # accidentally changed back to Tailscale's native DNS integration.
  tailscale_flags = [ "--accept-dns=false" ] ++ filter (arg: !hasPrefix "--accept-dns=" arg) cfg.extraArgs;
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

    services.resolved.enable = true;
    systemd.services.tailscale-dns = {
      description = "Configure Tailscale split DNS without host DNS takeover";
      wantedBy = [ "multi-user.target" "tailscaled.service" ];
      bindsTo = [ "tailscaled.service" "systemd-resolved.service" ];
      partOf = [ "tailscaled.service" "systemd-resolved.service" ];
      after = [ "tailscaled.service" "systemd-resolved.service" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "2s";
      };
      script = ''
        apply_dns() {
          if ${pkgs.iproute2}/bin/ip link show tailscale0 >/dev/null 2>&1; then
            ${pkgs.systemd}/bin/resolvectl dns tailscale0 100.100.100.100
            # Route only the tailnet domain to Quad100. The search domain
            # preserves single-label lookups such as `s3`.
            ${pkgs.systemd}/bin/resolvectl domain tailscale0 '~${cfg.tailnetDomain}' '${cfg.tailnetDomain}'
          fi
        }

        # The initial-state bit causes one immediate event; subsequent netmap
        # changes notify us when tailscaled internally resets its empty DNS
        # configuration, without a periodic polling loop.
        while true; do
          apply_dns
          ${pkgs.curl}/bin/curl --silent --no-buffer --show-error \
            --unix-socket /run/tailscale/tailscaled.sock \
            'http://local-tailscaled.sock/localapi/v0/watch-ipn-bus?mask=266' |
            while IFS= read -r event; do
              case "$event" in
                *'"NetMap":'*|*'"State":'*) apply_dns ;;
              esac
            done
          sleep 2
        done
      '';
    };

  };
}
