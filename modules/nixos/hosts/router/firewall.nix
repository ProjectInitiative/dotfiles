# modules/nixos/hosts/base-router/router/firewall.nix
{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.router;
  moduleCfg = config.${namespace}.router.firewall;
in
{
  options.${namespace}.router.firewall = with types; {
    allowPingFromWan = mkBoolOpt false "Allow ICMP Echo Requests from WAN";
    enable = mkBoolOpt true "Enable the firewall."; # Allow disabling firewall easily

    portForwarding = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            sourcePort = mkOption { type = types.int; };
            destination = mkOption { type = types.str; };
            destinationPort = mkOption { type = types.nullOr types.int; default = null; };
            protocol = mkOption { type = types.enum [ "tcp" "udp" ]; default = "tcp"; }; # Removed 'both' for simplicity with NixOS firewall
            description = mkOption { type = types.nullOr types.str; default = null; };
          };
        }
      );
      default = [ ];
      description = "List of port forwarding rules (DNAT)";
    };

    # Add options for allowed incoming services on LAN/VLANs if needed
    # e.g., allowDhcp = mkBoolOpt true; allowDns = mkBoolOpt true;
  };

  config = mkIf (cfg.enable && moduleCfg.enable) {

    networking.firewall = {
      enable = true; # Use the standard NixOS firewall
      allowPing = moduleCfg.allowPingFromWan; # Control ping from WAN via option

      # Define zones for clarity (optional but good practice)
      # zones = {
      #   wan = { interfaces = [ cfg.wanInterface ]; };
      #   lan = { interfaces = # All internal interfaces... tricky to build dynamically here, maybe skip zones
      #   };
      # };

      # Allowed TCP/UDP ports on the router itself from internal networks
      # Example: Allow SSH only from management network
      allowedTCPPorts = [ 22 ]; # Adjust as needed
      # allowedUDPPorts = [ 53 67 ]; # DNS, DHCP - handled by services usually

      # Forwarding rules for port forwarding (DNAT)
      forwardPorts = map (rule: {
        from = cfg.wanInterface;
        proto = rule.protocol;
        sourcePort = rule.sourcePort;
        destination = "${rule.destination}:${toString (fromMaybe rule.sourcePort rule.destinationPort)}";
      }) moduleCfg.portForwarding;


      # Extra rules for VLAN isolation and potentially other needs
      extraCommands = ''
        # --- VLAN Isolation Rules ---
        ${concatMapStrings (isolatedVlan:
          let isoInterface = "${cfg.lanInterface}.${toString isolatedVlan.id}";
          in concatMapStrings (otherVlan:
            let otherInterface = "${cfg.lanInterface}.${toString otherVlan.id}";
            in ''
              # Isolate VLAN ${toString isolatedVlan.id} (${isolatedVlan.name}) from VLAN ${toString otherVlan.id} (${otherVlan.name})
              iptables -A FORWARD -i ${isoInterface} -o ${otherInterface} -j REJECT --reject-with icmp-host-prohibited
              iptables -A FORWARD -i ${otherInterface} -o ${isoInterface} -j REJECT --reject-with icmp-host-prohibited
              # Add equivalent ip6tables rules if needed
            ''
          ) (filter (v: v.id != isolatedVlan.id) cfg.vlans)
        ) (filter (v: v.isolated) cfg.vlans)}

        # --- Allow established/related connections (Standard Rule, often implicit) ---
        # iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        # ip6tables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

        # --- Allow traffic from LAN/VLANs to WAN (Standard Rule, implicit with NAT) ---
        # Handled by NAT and default forward policy (if ACCEPT) or specific rules

        # --- Allow traffic from Management to anywhere (Example) ---
        # mgmt_if="${if cfg.managementVlan.id == 1 then cfg.lanInterface else "${cfg.lanInterface}.${toString cfg.managementVlan.id}"}"
        # iptables -A FORWARD -i $mgmt_if -j ACCEPT
        # iptables -A FORWARD -o $mgmt_if -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT # Allow return traffic

        # --- Default Forward Policy (Important!) ---
        # Consider setting default policy to DROP if not already done and explicitly allowing traffic.
        # NixOS default is usually ACCEPT for FORWARD chain if NAT is enabled. Check `iptables -L FORWARD`
        # To make it DROP:
        # iptables -P FORWARD DROP
        # Then add explicit ACCEPT rules for desired traffic flows (e.g., LAN -> WAN)

        # Allow VRRP (Protocol 112) - handled by keepalived module using firewall options
      '';

      # Allow multicast DNS if needed on LAN/VLANs
      # extraInputRules = ''
      #   iptables -A INPUT -p udp --dport 5353 -d 224.0.0.251 -j ACCEPT
      # '';
    };
  };
}
