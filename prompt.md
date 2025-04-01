Okay, let's break down this monolithic NixOS router configuration into more manageable, logical modules. This improves readability, maintainability, and reusability.

We'll create separate modules for:

1.  **Networking:** Handles base interfaces, VLANs, IP addressing, NAT, and basic routing settings (sysctl forwarding).
2.  **Firewall:** Manages firewall rules, including port forwarding and VLAN isolation.
3.  **DHCP (Kea):** Configures the Kea DHCPv4 server. We'll address the issue you pointed out – `services.dnsmasq.dhcp` isn't the standard way to configure DHCP relay/server in NixOS; we'll focus on the existing Kea configuration.
4.  **DNS (Dnsmasq):** Configures Dnsmasq purely as a DNS forwarder/cache.
5.  **VRRP (Keepalived):** Handles High Availability using Keepalived.
6.  **Kernel:** Manages extra kernel modules and sysctl settings not directly tied to basic forwarding.
7.  **Router (Main):** A top-level module to enable/disable the router functionality and import the others. It will hold the main options that influence multiple sub-modules (like `routerRole`, `managementVlan`, `vlans`, etc.).

**Directory Structure Suggestion:**

```
your-nixos-config/
├── hosts/
│   └── my-router.nix  # Your specific router host config
├── modules/
│   └── router/
│       ├── default.nix      # Main router module (imports others)
│       ├── networking.nix
│       ├── firewall.nix
│       ├── dhcp-kea.nix
│       ├── dns-dnsmasq.nix
│       ├── vrrp-keepalived.nix
│       └── kernel.nix
└── flake.nix
```

---

**1. `modules/router/default.nix` (Main Router Module)**

This module defines the main options and imports the sub-modules.

```nix
# modules/router/default.nix
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
  cfg = config.${namespace}.router; # Use a shorter path like 'router'
in
{
  imports = [
    ./networking.nix
    ./firewall.nix
    ./dhcp-kea.nix
    ./dns-dnsmasq.nix
    ./vrrp-keepalived.nix
    ./kernel.nix
  ];

  options.${namespace}.router = with types; {
    enable = mkBoolOpt false "Whether or not to enable the router configuration.";

    # --- Options moved here as they affect multiple modules ---
    wanInterface = mkOption {
      type = types.str;
      description = "The network interface connected to the internet/WAN";
      example = "wan0";
      default = "wan0";
    };

    lanInterface = mkOption {
      type = types.str;
      description = "The network interface connected to the internal network/LAN";
      example = "lan0";
      default = "lan0";
    };

    managementVlan = {
      id = mkOption {
        type = types.int;
        description = "Management VLAN ID for router administration";
        default = 1;
      };
      network = mkOption {
        type = types.str;
        description = "Management network in CIDR notation";
        example = "172.16.1.0/24";
        default = "172.16.1.0/24";
      };
      primaryIp = mkOption {
        type = types.str;
        description = "Primary router's IP on management network";
        example = "172.16.1.2";
        default = "172.16.1.2";
      };
      backupIp = mkOption {
        type = types.str;
        description = "Backup router's IP on management network";
        example = "172.16.1.3";
        default = "172.16.1.3";
      };
      virtualIp = mkOption {
        type = types.str;
        description = "Virtual IP for the active router on management network";
        example = "172.16.1.1";
        default = "172.16.1.1";
      };
      enableDhcp = mkOption {
        type = types.bool;
        description = "Whether to enable DHCP on the management VLAN (only if ID is 1 - untagged)";
        default = false; # Usually false for management
      };
      dhcpRangeStart = mkOption {
        type = types.nullOr types.str;
        description = "The start of the DHCP range (for management VLAN, if enabled)";
        example = "172.16.1.100";
        default = null;
      };
      dhcpRangeEnd = mkOption {
        type = types.nullOr types.str;
        description = "The end of the DHCP range (for management VLAN, if enabled)";
        example = "172.16.1.250";
        default = null;
      };
    };

    vlans = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            id = mkOption { type = types.int; description = "VLAN ID"; };
            name = mkOption { type = types.str; description = "VLAN name"; };
            network = mkOption { type = types.str; description = "VLAN network in CIDR notation"; };
            virtualIp = mkOption { type = types.str; description = "Virtual IP (VRRP) for this VLAN"; };
            primaryIp = mkOption { type = types.str; description = "Primary router's IP on this VLAN"; };
            backupIp = mkOption { type = types.str; description = "Backup router's IP on this VLAN"; };
            enableDhcp = mkOption { type = types.bool; default = true; description = "Enable DHCP"; };
            dhcpRangeStart = mkOption { type = types.str; description = "DHCP range start"; };
            dhcpRangeEnd = mkOption { type = types.str; description = "DHCP range end"; };
            isolated = mkOption { type = types.bool; default = false; description = "Isolate from other VLANs"; };
          };
        }
      );
      description = "List of VLANs to configure";
      default = [ ];
    };

    routerRole = mkOption {
      type = types.enum [ "primary" "backup" ];
      description = "Role of this router (primary or backup)";
      default = "primary";
    };

    enableIPv6 = mkOption {
      type = types.bool;
      description = "Whether to enable IPv6 support";
      default = true;
    };

    dnsServers = mkOption {
      type = types.listOf types.str;
      description = "DNS servers to use and provide to DHCP clients";
      default = [ "1.1.1.1" "9.9.9.9" ];
    };
  };

  config = mkIf cfg.enable {
    # Basic system settings needed for a router might go here or in host config
    # system.stateVersion = "23.11"; # Keep in host config

    # Enable IP forwarding (central place)
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
      "net.ipv6.conf.all.forwarding" = cfg.enableIPv6;
      # Basic security/sanity settings often needed for routers
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0; # Routers shouldn't send redirects unless specifically configured
      "net.ipv4.conf.default.send_redirects" = 0;
    };

    networking.enableIPv6 = cfg.enableIPv6;

    # Add base packages needed across modules if not handled per-module
    environment.systemPackages = with pkgs; [
      iproute2 # Essential for advanced networking
      iptables # Needed if using iptables backend for firewall
      tcpdump # Useful for debugging
      ethtool # Useful for interface diagnostics
    ];

    # Recommended: journald settings for a router
    services.journald = {
      rateLimitBurst = 0;
      extraConfig = "SystemMaxUse=50M";
    };

    # Parse networks for convenience (can be used by submodules)
    _module.args.parsedNetworks = let
       parseCIDR = cidr: {
         address = elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" cidr) 0;
         prefixLength = toInt (elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,2})$" cidr) 1);
       };
       mgmtParsed = parseCIDR cfg.managementVlan.network;
       vlansParsed = map (vlan: (parseCIDR vlan.network) // { inherit (vlan) id; }) cfg.vlans;
    in {
       management = mgmtParsed // { id = cfg.managementVlan.id; };
       vlans = vlansParsed;
    };

    assertions =
      [
        {
          assertion = builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" cfg.managementVlan.network != null;
          message = "Management network must be in valid CIDR notation (e.g., 172.16.1.0/24)";
        }
        {
            assertion = cfg.managementVlan.id != 1 -> !(cfg.managementVlan.enableDhcp);
            message = "DHCP can only be enabled on the management VLAN if its ID is 1 (untagged LAN)";
        }
        {
            assertion = !(cfg.managementVlan.enableDhcp) || (cfg.managementVlan.dhcpRangeStart != null && cfg.managementVlan.dhcpRangeEnd != null);
            message = "Management VLAN DHCP requires dhcpRangeStart and dhcpRangeEnd to be set.";
        }
      ]
      ++ (map (vlan: {
        assertion = builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" vlan.network != null;
        message = "VLAN network ${vlan.name} must be in valid CIDR notation";
      }) cfg.vlans)
      ++ (map (vlan: {
        assertion = !(vlan.enableDhcp) || (vlan.dhcpRangeStart != null && vlan.dhcpRangeEnd != null);
        message = "VLAN ${vlan.name} DHCP requires dhcpRangeStart and dhcpRangeEnd to be set.";
      }) (filter (v: v.enableDhcp) cfg.vlans));

  };
}
```

---

**2. `modules/router/networking.nix`**

```nix
# modules/router/networking.nix
{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  parsedNetworks, # Passed via _module.args
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.router;
  moduleCfg = config.${namespace}.router.networking;
in
{
  options.${namespace}.router.networking = with types; {
    externalStaticIp = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            address = mkOption { type = types.str; description = "Static external IP address"; };
            prefixLength = mkOption { type = types.int; description = "Prefix length"; };
            gateway = mkOption { type = types.str; description = "Default gateway"; };
          };
        }
      );
      default = null;
      description = "Static external IP configuration (null for DHCP)";
    };

    # Potentially add more networking-specific options here later
  };

  config = mkIf cfg.enable {

    # Define VLAN devices
    networking.vlans = listToAttrs (
      map (vlan: {
        name = "${cfg.lanInterface}.${toString vlan.id}";
        value = {
          id = vlan.id;
          interface = cfg.lanInterface;
        };
      }) cfg.vlans
      # Add management VLAN if it's tagged
      ++ optional (cfg.managementVlan.id != 1) {
           name = "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
           value = {
             id = cfg.managementVlan.id;
             interface = cfg.lanInterface;
           };
         }
    );

    networking.useDHCP = false; # We configure interfaces manually

    # Configure Interfaces (WAN, LAN/Management, VLANs)
    networking.interfaces = let
      getIp = roleAttrPrefix: if cfg.routerRole == "primary" then "${roleAttrPrefix}PrimaryIp" else "${roleAttrPrefix}BackupIp";
      getVlanIp = vlan: if cfg.routerRole == "primary" then vlan.primaryIp else vlan.backupIp;

      mgmtIp = if cfg.routerRole == "primary" then cfg.managementVlan.primaryIp else cfg.managementVlan.backupIp;
      mgmtInterfaceName = if cfg.managementVlan.id == 1 then cfg.lanInterface else "${cfg.lanInterface}.${toString cfg.managementVlan.id}";

    in {
      # WAN Interface
      "${cfg.wanInterface}" = {
          useDHCP = moduleCfg.externalStaticIp == null;
          ipv4 = mkIf (moduleCfg.externalStaticIp != null) {
            addresses = [{
              address = moduleCfg.externalStaticIp.address;
              prefixLength = moduleCfg.externalStaticIp.prefixLength;
            }];
          };
          # Basic IPv6 WAN setup (assuming SLAAC/DHCPv6 from ISP)
          ipv6 = mkIf cfg.enableIPv6 {
              addresses = []; # Let RA handle it
              acceptRA = true;
              # useDHCP = true; # If your ISP uses DHCPv6 for addresses
          };
      };

      # Management Interface (Tagged or Untagged)
      "${mgmtInterfaceName}" = {
         ipv4.addresses = [{
           address = mgmtIp;
           prefixLength = parsedNetworks.management.prefixLength;
         }];
         ipv6.addresses = []; # Assuming manual or static internal IPv6 later if needed
      };

      # Other VLAN Interfaces
    } // listToAttrs (
      map (vlan: {
        name = "${cfg.lanInterface}.${toString vlan.id}";
        value = {
          ipv4.addresses = [{
            address = getVlanIp vlan;
            prefixLength = (findFirst (pn: pn.id == vlan.id) null parsedNetworks.vlans).prefixLength;
          }];
          ipv6.addresses = []; # Assuming manual or static internal IPv6 later if needed
        };
      }) cfg.vlans
    );

    # Default Gateway
    networking.defaultGateway = mkIf (moduleCfg.externalStaticIp != null) {
      address = moduleCfg.externalStaticIp.gateway;
      interface = cfg.wanInterface;
    };
    # Note: Default gateway via DHCP is handled automatically if useDHCP=true for WAN

    # NAT Configuration
    networking.nat = {
      enable = true;
      externalInterface = cfg.wanInterface;
      internalInterfaces = let
          mgmtInterfaceName = if cfg.managementVlan.id == 1 then cfg.lanInterface else "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
      in [ mgmtInterfaceName ] ++ (map (vlan: "${cfg.lanInterface}.${toString vlan.id}") cfg.vlans);
      # internalIPs should not be needed if internalInterfaces is correct
    };

    # IPv6 Router Advertisements (basic example, needs customization)
    services.radvd = mkIf cfg.enableIPv6 {
        enable = true;
        config = let
            mkPrefix = networkInfo: ''
              prefix ${networkInfo.address}/${toString networkInfo.prefixLength}
              {
                  AdvOnLink on;
                  AdvAutonomous on;
                  AdvRouterAddr on;
              };
            '';
            # This assumes you have manually assigned IPv6 prefixes or derived them somehow
            # Replace with your actual IPv6 prefixes for each VLAN/LAN
            # Example: ULA prefix or delegated prefix from ISP
            # mgmtPrefix6 = "fd00:1::/64";
            # vlanPrefixes6 = { 10 = "fd00:10::/64"; 20 = "fd00:20::/64"; };
            mgmtInterfaceName = if cfg.managementVlan.id == 1 then cfg.lanInterface else "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
        in ''
          interface ${mgmtInterfaceName} {
              AdvSendAdvert on;
              # ${mkPrefix { address="YOUR_MGMT_IPV6_PREFIX"; prefixLength=64; }}
              # Route info if needed
              # route ::/0 {};
              # RDNSS info (recursive DNS servers)
              RDNSS ${concatStringsSep " " cfg.dnsServers} {};
          };
        '' + concatMapStrings (vlan:
            let vlanInterfaceName = "${cfg.lanInterface}.${toString vlan.id}";
            in ''
              interface ${vlanInterfaceName} {
                  AdvSendAdvert on;
                  # ${mkPrefix { address="YOUR_VLAN_${toString vlan.id}_IPV6_PREFIX"; prefixLength=64; }}
                  # Route info if needed
                  # route ::/0 {};
                  RDNSS ${concatStringsSep " " cfg.dnsServers} {};
              };
            ''
        ) cfg.vlans;
    };

    # Required packages
    environment.systemPackages = with pkgs; [ vlan ];
  };
}
```

---

**3. `modules/router/firewall.nix`**

```nix
# modules/router/firewall.nix
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
```

---

**4. `modules/router/dhcp-kea.nix`**

```nix
# modules/router/dhcp-kea.nix
{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  parsedNetworks, # Passed via _module.args
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.router;
  moduleCfg = config.${namespace}.router.dhcp;

  # Helper to generate subnet config
  mkSubnetConfig = { networkInfo, vlanCfg }: {
      subnet = networkInfo.address + "/" + toString networkInfo.prefixLength;
      pools = [ { pool = "${vlanCfg.dhcpRangeStart} - ${vlanCfg.dhcpRangeEnd}"; } ];
      option-data = [
        { name = "routers"; data = vlanCfg.virtualIp; }
        { name = "domain-name-servers"; data = concatStringsSep "," cfg.dnsServers; }
        # Add other DHCP options here if needed
      ];
      # Add reservations here if needed
      # reservations = [ { hw-address = "..."; ip-address = "..."; } ];
  };

in
{
  options.${namespace}.router.dhcp = with types; {
    # Simplified Kea options
    kea = {
      enable = mkBoolOpt false "Whether to enable Kea DHCPv4 server.";

      # Interfaces Kea should listen on (derived automatically)
      # interfaces = mkOption { type = types.listOf types.str; default = []; };

      failover = mkOption {
        type = types.nullOr (types.submodule {
          options = {
            # partnerAddress automatically derived from peerAddress in vrrp config
            # port = mkOption { type = types.port; default = 647; }; # Kea default
            maxUnackedUpdates = mkOption { type = types.int; default = 10; };
            maxAckDelay = mkOption { type = types.int; default = 1000; }; # ms
            mclt = mkOption { type = types.int; default = 3600; }; # seconds
            # hba = mkOption { type = types.int; default = 10; }; # Kea >= 1.6 removed this
            # load-balancing mode options can be added here if needed
          };
        });
        default = null;
        description = "Failover configuration for Kea DHCPv4.";
      };
    };
  };

  config = mkIf (cfg.enable && moduleCfg.kea.enable) {

    # Determine listening interfaces for Kea
    _module.args.keaInterfaces = let
        mgmtInterfaceName = if cfg.managementVlan.id == 1 then cfg.lanInterface else "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
        # Only include management interface if DHCP is enabled for it (only possible if ID=1)
        mgmtIf = optional (cfg.managementVlan.id == 1 && cfg.managementVlan.enableDhcp) mgmtInterfaceName;
        vlanIfs = map (vlan: "${cfg.lanInterface}.${toString vlan.id}") (filter (v: v.enableDhcp) cfg.vlans);
    in mgmtIf ++ vlanIfs;


    services.kea-dhcp4 = {
      enable = true;
      settings = {
        Dhcp4 = {
          interfaces-config = {
            interfaces = config._module.args.keaInterfaces; # Use dynamically generated list
            # Specify dhcp-socket-type=raw for performance if needed and supported
          };

          # Lease database configuration (Memfile is default, consider MySQL/PostgreSQL for HA)
          lease-database = {
             type = "memfile";
             lfc-interval = 3600;
          };
          # Example PostgreSQL:
          # lease-database = {
          #   type = "postgresql";
          #   name = "kea"; # Database name
          #   host = "your_db_host";
          #   user = "kea";
          #   password = "kea_password";
          # };

          # Define subnets based on router config
          subnet4 = let
             # Management subnet (only if ID=1 and DHCP enabled)
             mgmtSubnet = optional (cfg.managementVlan.id == 1 && cfg.managementVlan.enableDhcp)
               (mkSubnetConfig {
                 networkInfo = parsedNetworks.management;
                 vlanCfg = cfg.managementVlan; # Use the managementVlan options directly
               });
             # VLAN subnets
             vlanSubnets = map (vlan:
                mkSubnetConfig {
                  networkInfo = findFirst (pn: pn.id == vlan.id) null parsedNetworks.vlans;
                  vlanCfg = vlan;
                }
             ) (filter (v: v.enableDhcp) cfg.vlans);
          in mgmtSubnet ++ vlanSubnets;

          # High Availability / Failover Hookups
          "ha-hooks" = mkIf (moduleCfg.kea.failover != null) {
             hook-libraries = [
                { library = "${pkgs.kea}/lib/kea/hooks/libdhcp_ha.so";
                  parameters = {
                      high-availability = [
                          {
                              this-server-name = if cfg.routerRole == "primary" then "kea-router1" else "kea-router2"; # Names must match partner's config
                              mode = "load-balancing"; # or "hot-standby"
                              heartbeat-delay = 10000; # ms
                              max-response-delay = 10000; # ms
                              max-ack-delay = moduleCfg.kea.failover.maxAckDelay; # ms
                              max-unacked-clients = moduleCfg.kea.failover.maxUnackedUpdates;

                              peers = [
                                  {
                                      name = if cfg.routerRole == "primary" then "kea-router2" else "kea-router1"; # Partner's name
                                      # Kea derives partner IP and port from VRRP config if possible, or set explicitly
                                      url = "http://${config.${namespace}.router.vrrp.peerAddress}:${toString config.${namespace}.router.vrrp.keaFailoverPort}"; # Use explicit port from VRRP options
                                      role = if cfg.routerRole == "primary" then "primary" else "secondary"; # Role in this specific peer relationship
                                      # auto-failover = true; # Default
                                  }
                              ];
                          }
                      ];
                  };
                }
             ];
          };

          # Logging (optional, customize as needed)
          loggers = [
            {
              name = "kea-dhcp4";
              output_options = [{ output = "stderr"; }]; # or syslog, file
              severity = "INFO"; # DEBUG, WARN, ERROR etc.
            }
          ];
        };
      };
    };

    # Required packages
    environment.systemPackages = with pkgs; [ kea ];

    # Open firewall port for Kea HA communication if failover enabled
    networking.firewall = mkIf (moduleCfg.kea.failover != null) {
        allowedUDPPorts = [ config.${namespace}.router.vrrp.keaFailoverPort ]; # Allow incoming HA connections
        # Or more specific rule using peer address:
        # extraCommands = ''
        #   iptables -A INPUT -p tcp --dport ${toString config.${namespace}.router.vrrp.keaFailoverPort} -s ${config.${namespace}.router.vrrp.peerAddress} -j ACCEPT
        # '';
    };

  };
}
```

---

**5. `modules/router/dns-dnsmasq.nix`**

```nix
# modules/router/dns-dnsmasq.nix
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
  moduleCfg = config.${namespace}.router.dns;
in
{
  options.${namespace}.router.dns = with types; {
    enable = mkBoolOpt true "Whether to enable Dnsmasq as a DNS forwarder/cache.";
    # Add more dnsmasq specific options if needed, e.g., cache size
    cacheSize = mkOption {
        type = types.int;
        default = 1000;
        description = "DNS cache size for dnsmasq.";
    };
    # cfg.dnsServers is used from the main router config for upstream servers
  };

  config = mkIf (cfg.enable && moduleCfg.enable) {

    services.dnsmasq = {
      enable = true;
      # Listen only on internal interfaces (including virtual IPs for HA)
      extraConfig = let
        mgmtInterfaceName = if cfg.managementVlan.id == 1 then cfg.lanInterface else "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
        interfaces = [ mgmtInterfaceName ] ++ (map (vlan: "${cfg.lanInterface}.${toString vlan.id}") cfg.vlans);
        # Listen on physical IPs *and* virtual IPs
        listenAddresses = let
            mgmtIp = if cfg.routerRole == "primary" then cfg.managementVlan.primaryIp else cfg.managementVlan.backupIp;
            mgmtVip = cfg.managementVlan.virtualIp;
            vlanIps = map (vlan: if cfg.routerRole == "primary" then vlan.primaryIp else vlan.backupIp) cfg.vlans;
            vlanVips = map (vlan: vlan.virtualIp) cfg.vlans;
        in [ mgmtIp ] ++ optional (config.${namespace}.router.vrrp.enable) mgmtVip ++ vlanIps ++ optional (config.${namespace}.router.vrrp.enable) vlanVips;

      in ''
        # Do NOT run DHCP server here
        no-dhcp-interface=*

        # Listen on specific IPs (Physical + Virtual)
        ${concatMapStrings (ip: "listen-address=${ip}\n") listenAddresses}
        # Alternatively, bind only to interfaces:
        # ${concatMapStrings (iface: "interface=${iface}\n") interfaces}
        # bind-interfaces # Use with interface= lines

        # Set DNS cache size
        cache-size=${toString moduleCfg.cacheSize}

        # Add local domain if needed
        # local=/your.internal.domain/
        # domain=your.internal.domain

        # Add custom DNS records if needed
        # address=/my-server.your.internal.domain/192.168.1.50
      '';

      servers = cfg.dnsServers; # Upstream DNS servers
    };

    # Open firewall port for DNS (UDP/TCP 53) on internal interfaces
    networking.firewall = {
      allowedUDPPorts = [ 53 ];
      allowedTCPPorts = [ 53 ];
      # Could restrict to specific interfaces/zones if needed
    };
  };
}
```

---

**6. `modules/router/vrrp-keepalived.nix`**

```nix
# modules/router/vrrp-keepalived.nix
{
  options,
  config,
  lib,
  pkgs,
  namespace,
  modulesPath,
  sops, # Need sops if password is encrypted
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.router;
  moduleCfg = config.${namespace}.router.vrrp;
in
{
  options.${namespace}.router.vrrp = with types; {
    enable = mkBoolOpt true "Whether to enable VRRP (Keepalived) for high availability.";

    # VRRP base ID and priority can be adjusted per-router in host config
    virtualRouterIdBase = mkOption {
      type = types.int;
      default = 10;
      description = "Base VRRP Virtual Router ID (incremented for each VLAN)";
    };

    priority = mkOption {
      type = types.int;
      default = 100; # Primary typically > 100, Backup < 100
      description = "VRRP priority for this router (higher wins). Set based on routerRole.";
    };

    # Password should ideally come from sops or similar
    authPassFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a file containing the VRRP authentication password.";
      example = ''sops.secrets."keepalived_vrrp_password".path'';
    };
    authPass = mkOption {
       type = types.nullOr types.str;
       default = null;
       description = "VRRP authentication password (plain text, use authPassFile instead).";
    };

    # Peer address derived automatically from managementVlan IPs based on role
    # peerAddress = mkOption { type = types.str; description = "IP address of the peer router on the management VLAN"; };

    keaFailoverPort = mkOption {
      type = types.port;
      default = 647; # Default Kea HA port
      description = "Port used for Kea DHCP failover communication (if enabled).";
    };

    notifyMasterScript = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Shell command or script path to run when this node becomes MASTER.";
    };
    notifyBackupScript = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Shell command or script path to run when this node becomes BACKUP.";
    };
    notifyFaultScript = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Shell command or script path to run when this node enters FAULT state.";
    };
  };

  config = mkIf (cfg.enable && moduleCfg.enable) {

    assertions = [
        { assertion = moduleCfg.authPass != null || moduleCfg.authPassFile != null;
          message = "Either vrrp.authPass or vrrp.authPassFile must be set when VRRP is enabled.";
        }
        { assertion = !(moduleCfg.authPass != null && moduleCfg.authPassFile != null);
          message = "Cannot set both vrrp.authPass and vrrp.authPassFile.";
        }
    ];

    _module.args.vrrpPassword = if moduleCfg.authPassFile != null
        then builtins.readFile moduleCfg.authPassFile
        else moduleCfg.authPass;

    # Automatically determine peer address
    _module.args.peerAddress = if cfg.routerRole == "primary"
        then cfg.managementVlan.backupIp
        else cfg.managementVlan.primaryIp;

    # Automatically set priority based on role
    _module.args.vrrpPriority = if cfg.routerRole == "primary"
        then moduleCfg.priority # Use the configured priority for primary
        else moduleCfg.priority - 50; # Backup is lower (adjust logic as needed)

    services.keepalived = {
      enable = true;
      # global_defs might not be needed if router_id is not globally required by scripts
      # global_defs = { router_id = "router_${cfg.routerRole}"; };

      vrrpScripts = {
          # Example check script (e.g., check WAN connectivity)
          # chk_wan = {
          #   script = "${pkgs.runtimeShell} -c 'ping -c 1 8.8.8.8 &> /dev/null'";
          #   interval = 2; # seconds
          #   fall = 2; # require 2 failures to fall
          #   rise = 2; # require 2 successes to rise
          #   weight = 10; # Adjust priority by this amount on failure
          # };
      };

      vrrpInstances = let
         mkInstance = { name, vlanId, virtualIp, networkInfo }: {
            # Instance name must be unique on the host
            # Using VLAN ID ensures uniqueness
            state = if cfg.routerRole == "primary" then "MASTER" else "BACKUP";
            interface = if vlanId == 1 then cfg.lanInterface else "${cfg.lanInterface}.${toString vlanId}";
            virtualRouterId = moduleCfg.virtualRouterIdBase + vlanId; # Unique VRID per VLAN/subnet
            priority = config._module.args.vrrpPriority;
            advertInt = 1; # seconds
            authentication = {
                authType = "PASS";
                authPass = config._module.args.vrrpPassword;
            };
            # unicastPeer = [ config._module.args.peerAddress ]; # Use unicast for direct communication
            virtualIPAddresses = [
                { ip = virtualIp; # IPv4 VIP
                  # prefix = networkInfo.prefixLength; # Not needed for address object
                }
                # Add IPv6 VIPs here if used
                # { ip = "YOUR_IPV6_VIP"; dev = if vlanId == 1 then cfg.lanInterface else "..."; }
            ];

            # Scripts to run on state change
            notifyMaster = moduleCfg.notifyMasterScript;
            notifyBackup = moduleCfg.notifyBackupScript;
            notifyFault = moduleCfg.notifyFaultScript;

            # Track scripts (optional, adjust priority based on script success/failure)
            # trackScript = [ "chk_wan" ];
         };

         mgmtInstance = mkInstance {
            name = "MGMT";
            vlanId = cfg.managementVlan.id;
            virtualIp = cfg.managementVlan.virtualIp;
            networkInfo = config._module.args.parsedNetworks.management;
         };

         vlanInstances = listToAttrs (map (vlan: {
            name = "VLAN_${toString vlan.id}"; # Keepalived instance name needs to be attr name
            value = mkInstance {
                name = vlan.name; # Descriptive name for logs etc.
                vlanId = vlan.id;
                virtualIp = vlan.virtualIp;
                networkInfo = findFirst (pn: pn.id == vlan.id) null config._module.args.parsedNetworks.vlans;
            };
         }) cfg.vlans);

      in { "MGMT_VRRP" = mgmtInstance; } // vlanInstances; # Combine mgmt and VLAN instances
    };

    # Firewall rules for VRRP (Protocol 112)
    networking.firewall.allowedProtocols = [ "vrrp" ]; # Protocol 112
    # Or more specific rules if needed:
    # networking.firewall.extraCommands = ''
    #   iptables -A INPUT -p vrrp -s ${config._module.args.peerAddress} -j ACCEPT
    #   iptables -A OUTPUT -p vrrp -d ${config._module.args.peerAddress} -j ACCEPT
    # '';

    # Packages
    environment.systemPackages = with pkgs; [ keepalived ];
  };
}
```

---

**7. `modules/router/kernel.nix`**

```nix
# modules/router/kernel.nix
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
  moduleCfg = config.${namespace}.router.kernel;
in
{
  options.${namespace}.router.kernel = with types; {
    extraModules = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional kernel modules to load.";
    };
    extraSysctl = mkOption {
      type = types.attrsOf types.anything; # Allow any valid sysctl value type
      default = { };
      description = "Additional custom sysctl settings.";
    };
  };

  config = mkIf cfg.enable {
    boot = {
      kernelModules = [
        # Base modules needed for routing/firewalling/NAT/VLANs
        "nf_nat"          # General NAT connection tracking helper
        "nf_conntrack"    # Connection tracking core
        # "iptable_nat"     # Replaced by nf_nat generally
        # "iptable_filter"  # Loaded by default usually
        "nf_reject_ipv4"  # For REJECT target
        "nf_reject_ipv6"  # For REJECT target (if using ip6tables)
        "ip_tables"       # Core iptables module
        "8021q"           # VLAN support
      ] ++ moduleCfg.extraModules;

      # Kernel sysctl settings beyond basic forwarding (already in default.nix)
      kernel.sysctl = {
        # Recommended security/performance settings for a router
        "net.ipv4.tcp_syncookies" = 1; # Mitigate SYN floods
        "net.ipv4.conf.all.rp_filter" = 1; # Enable strict reverse path filtering
        "net.ipv4.conf.default.rp_filter" = 1;
        "net.ipv4.conf.all.log_martians" = 1; # Log packets with impossible source addresses
        "net.ipv4.conf.default.log_martians" = 1;

        # IPv6 settings beyond basic forwarding/RA (already in default.nix)
        "net.ipv6.conf.all.accept_ra" = 0; # Don't accept RAs on internal interfaces by default
        "net.ipv6.conf.default.accept_ra" = 0;
        "net.ipv6.conf.all.autoconf" = 0; # Don't autoconfigure addresses internally
        "net.ipv6.conf.default.autoconf" = 0;
        "net.ipv6.conf.all.use_tempaddr" = 0; # Routers typically don't need temporary addresses

        # Adjust WAN interface specifically if needed (done in networking.nix now)
        # "net.ipv6.conf.${cfg.wanInterface}.accept_ra" = mkIf cfg.enableIPv6 2; # Accept even if forwarding
        # "net.ipv6.conf.${cfg.wanInterface}.autoconf" = mkIf cfg.enableIPv6 1;

        # Add custom settings from config
      } // moduleCfg.extraSysctl;
    };
  };
}
```

---

**8. Example Host Configuration (`hosts/my-router.nix`)**

Now, your actual host configuration becomes much cleaner:

```nix
# hosts/my-router.nix
{
  config,
  pkgs,
  lib,
  namespace,
  inputs, # Assuming flake input 'sops-nix'
  ...
}:
with lib;
with lib.${namespace};
let
  # Define router role here or via hostname check etc.
  routerRole = "primary"; # or "backup"
in
{
  imports = [
    # Import the main router module
    ../modules/router

    # Import sops module if needed for secrets
    inputs.sops-nix.nixosModules.sops
  ];

  # --- Basic Host Settings ---
  system.stateVersion = "23.11"; # Or your current version
  networking.hostName = "router-${routerRole}";
  time.timeZone = "Europe/London";

  # Enable SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };
  users.users.admin = { # Example admin user
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ]; # networkmanager might not be needed if fully manual
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA..."
    ];
    # Set password via sops or impermanence
  };
  # users.users.root.hashedPasswordFile = config.sops.secrets.root_password.path;

  # --- Router Configuration ---
  ${namespace}.router = {
    enable = true;
    routerRole = routerRole; # Pass role defined above

    # --- Interfaces ---
    wanInterface = "eth0"; # Adjust to your hardware
    lanInterface = "eth1"; # Adjust to your hardware

    # --- Management Network ---
    managementVlan = {
      id = 10; # Tagged management VLAN
      network = "172.16.10.0/24";
      primaryIp = "172.16.10.2";
      backupIp = "172.16.10.3";
      virtualIp = "172.16.10.1";
      # enableDhcp = false; # Default is false
    };

    # --- User VLANs ---
    vlans = [
      {
        id = 20;
        name = "users";
        network = "192.168.20.0/24";
        primaryIp = "192.168.20.2";
        backupIp = "192.168.20.3";
        virtualIp = "192.168.20.1";
        enableDhcp = true;
        dhcpRangeStart = "192.168.20.100";
        dhcpRangeEnd = "192.168.20.200";
      }
      {
        id = 30;
        name = "iot";
        network = "192.168.30.0/24";
        primaryIp = "192.168.30.2";
        backupIp = "192.168.30.3";
        virtualIp = "192.168.30.1";
        enableDhcp = true;
        dhcpRangeStart = "192.168.30.50";
        dhcpRangeEnd = "192.168.30.150";
        isolated = true; # Isolate this VLAN
      }
    ];

    # --- WAN IP ---
    networking.externalStaticIp = {
      address = "YOUR_STATIC_IP";
      prefixLength = 24; # Your prefix length
      gateway = "YOUR_GATEWAY_IP";
    };
    # Or set networking.externalStaticIp = null; to use DHCP on WAN

    # --- DNS ---
    dnsServers = [ "9.9.9.9" "1.1.1.1" ]; # Override defaults if needed
    dns.cacheSize = 2000; # Customize DNS cache

    # --- DHCP ---
    dhcp.kea.enable = true;
    dhcp.kea.failover = mkIf config.${namespace}.router.vrrp.enable { # Enable failover only if VRRP is enabled
       # Parameters are mostly defaults, adjust if needed
       mclt = 1800; # Example override
    };


    # --- VRRP / Keepalived ---
    vrrp.enable = true; # Enable HA
    vrrp.virtualRouterIdBase = 50; # Customize base VRID
    vrrp.priority = if routerRole == "primary" then 150 else 100; # Explicit priorities
    # vrrp.authPass = "supersecret"; # Use authPassFile instead
    vrrp.authPassFile = config.sops.secrets."keepalived_vrrp_password".path;
    vrrp.keaFailoverPort = 647; # Ensure this matches Kea config if using failover

    # --- Firewall ---
    firewall.allowPingFromWan = false;
    firewall.portForwarding = [
      { sourcePort = 80; destination = "192.168.20.10"; protocol = "tcp"; description = "Web Server"; }
      { sourcePort = 443; destination = "192.168.20.10"; protocol = "tcp"; }
      { sourcePort = 1194; destination = "192.168.20.11"; destinationPort = 1194; protocol = "udp"; description = "OpenVPN"; }
    ];

    # --- Kernel ---
    kernel.extraModules = [ "wireguard" ]; # Example
    kernel.extraSysctl = {
      "net.core.somaxconn" = 1024; # Example custom sysctl
    };

  };

  # --- SOPS Configuration (Example) ---
  sops.secrets."keepalived_vrrp_password" = {
      # mode = "0400"; # keepalived runs as root, default mode is fine
      # owner = config.users.users.keepalived.name; # Not needed if root reads it
  };
  # sops.secrets."root_password" = {};

  # Optional: Disable NetworkManager if managing interfaces manually
  networking.networkmanager.enable = false;
  # Or configure NetworkManager to ignore managed interfaces:
  # networking.networkmanager.unmanaged = [ "eth0" "eth1" "eth1.*" ];


}
```

This modular structure makes the configuration much easier to navigate and understand. Each file focuses on a specific aspect of the router's functionality. Remember to adjust interface names, IP addresses, VLAN IDs, and secrets according to your specific environment.
