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
  cfg = config.${namespace}.hosts.base-router;
  sops = config.sops;
in
{
  options.${namespace}.hosts.base-router = with types; {
    enable = mkBoolOpt false "Whether or not to enable the masthead router base config.";

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

    # Management VLAN for router administration
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
    };

    dhcpRangeStart = mkOption {
      type = types.str;
      description = "The start of the DHCP range (for default network)";
      example = "192.168.1.100";
      default = "192.168.1.100";
    };

    dhcpRangeEnd = mkOption {
      type = types.str;
      description = "The end of the DHCP range (for default network)";
      example = "192.168.1.250";
      default = "192.168.1.250";
    };

    externalStaticIp = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            address = mkOption {
              type = types.str;
              description = "The static external IP address";
              example = "203.0.113.10";
            };
            prefixLength = mkOption {
              type = types.int;
              description = "The prefix length of the external IP";
              example = 24;
            };
            gateway = mkOption {
              type = types.str;
              description = "The default gateway address";
              example = "203.0.113.1";
            };
          };
        }
      );
      description = "Static external IP configuration (null for DHCP)";
      default = null;
    };

    dnsServers = mkOption {
      type = types.listOf types.str;
      description = "DNS servers to use and provide to DHCP clients";
      default = [
        "1.1.1.1"
        "9.9.9.9"
      ];
    };

    enableIPv6 = mkOption {
      type = types.bool;
      description = "Whether to enable IPv6 support";
      default = true;
    };

    portForwarding = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            sourcePort = mkOption {
              type = types.int;
              description = "External source port";
            };
            destination = mkOption {
              type = types.str;
              description = "Internal destination IP";
            };
            destinationPort = mkOption {
              type = types.int;
              description = "Internal destination port";
              default = null;
            };
            protocol = mkOption {
              type = types.enum [
                "tcp"
                "udp"
                "both"
              ];
              description = "Protocol for port forwarding";
              default = "tcp";
            };
          };
        }
      );
      description = "List of port forwarding rules";
      default = [ ];
    };

    extraKernelModules = mkOption {
      type = types.listOf types.str;
      description = "Additional kernel modules to load";
      default = [ ];
    };

    extraSysctlSettings = mkOption {
      type = types.attrsOf types.anything;
      description = "Additional sysctl settings";
      default = { };
    };

    # VLAN configuration with support for routing and DHCP
    vlans = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            id = mkOption {
              type = types.int;
              description = "VLAN ID";
              example = 21;
            };

            name = mkOption {
              type = types.str;
              description = "VLAN name";
              example = "iot";
            };

            network = mkOption {
              type = types.str;
              description = "VLAN network in CIDR notation";
              example = "192.168.21.0/24";
            };

            virtualIp = mkOption {
              type = types.str;
              description = "Virtual IP (VRRP) for this VLAN";
              example = "192.168.21.1";
            };

            primaryIp = mkOption {
              type = types.str;
              description = "Primary router's IP on this VLAN";
              example = "192.168.21.2";
            };

            backupIp = mkOption {
              type = types.str;
              description = "Backup router's IP on this VLAN";
              example = "192.168.21.3";
            };

            enableDhcp = mkOption {
              type = types.bool;
              description = "Whether to enable DHCP on this VLAN";
              default = true;
            };

            dhcpRangeStart = mkOption {
              type = types.str;
              description = "The start of the DHCP range for this VLAN";
              example = "192.168.21.100";
            };

            dhcpRangeEnd = mkOption {
              type = types.str;
              description = "The end of the DHCP range for this VLAN";
              example = "192.168.21.250";
            };

            isolated = mkOption {
              type = types.bool;
              description = "Whether this VLAN should be isolated from other VLANs";
              default = false;
            };
          };
        }
      );
      description = "List of VLANs to configure";
      default = [ ];
    };

    # Router role configuration (can be set at host level)
    routerRole = mkOption {
      type = types.enum [
        "primary"
        "backup"
      ];
      description = "Role of this router (primary or backup)";
      example = "primary";
      default = "primary";
    };
    
    # DHCP source configuration
    dhcpMode = mkOption {
      type = types.enum [
        "internal"  # Use internal DHCP server
        "external"  # Forward DHCP to external server
      ];
      description = "DHCP server mode";
      default = "internal";
    };
    
    # External DHCP server IP (when using external DHCP)
    externalDhcpServer = mkOption {
      type = types.nullOr types.str;
      description = "IP address of external DHCP server (when dhcpMode is external)";
      example = "192.168.1.5";
      default = null;
    };
    
    # VRRP/keepalived configuration
    vrrp = {
      enable = mkOption {
        type = types.bool;
        description = "Whether to enable VRRP for high availability";
        default = true;
      };

      routerId = mkOption {
        type = types.int;
        description = "Unique VRRP router ID";
        default = 10;
      };

      priority = mkOption {
        type = types.int;
        description = "VRRP priority (higher number = higher priority)";
        default = 100;
      };

      authPass = mkOption {
        type = types.str;
        description = "VRRP authentication password";
      };

      peerAddress = mkOption {
        type = types.str;
        description = "IP address of the peer router on the management VLAN";
        example = "172.16.1.3";
      };

      notifyMaster = mkOption {
        type = types.nullOr types.str;
        description = "Script to run when this node becomes the master";
        default = null;
      };

      notifyBackup = mkOption {
        type = types.nullOr types.str;
        description = "Script to run when this node becomes the backup";
        default = null;
      };
    };
  };

  config = mkIf cfg.enable {
    # Basic system configuration
    system.stateVersion = "23.11";

    # Enable displaying network info on console
    projectinitiative = {
      system = {
        console-info = {
          ip-display = enabled;
        };
      };
    };

    networking.networkmanager.enable = true;

    # Add your other configuration options here
    services.openssh.enable = true;
    users.users.root.hashedPasswordFile = sops.secrets.root_password.path;
    programs.zsh.enable = true;

    # Extract network details and router role
    _module.args.routerConfig = cfg;
    _module.args.isPrimary = cfg.routerRole == "primary";

    # Parse the CIDR notation for management network
    assertions =
      [
        {
          assertion =
            builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" cfg.managementVlan.network
            != null;
          message = "Management network must be in valid CIDR notation (e.g., 172.16.1.0/24)";
        }
      ]
      ++ (map (vlan: {
        assertion =
          builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" vlan.network
          != null;
        message = "VLAN network ${vlan.name} must be in valid CIDR notation";
      }) cfg.vlans);

    # Enable IP forwarding and load necessary kernel modules
    boot = {
      kernelModules = [
        # Basic firewall modules
        "iptable_nat"
        "iptable_filter"
        "xt_nat"
        # Add 8021q module for VLAN support
        "8021q"
      ] ++ cfg.extraKernelModules;

      kernel.sysctl = {
        # Base security settings
        "net.ipv4.tcp_syncookies" = true;
        "net.ipv4.conf.all.forwarding" = true;
        "net.ipv4.conf.all.rp_filter" = true;
        "net.ipv4.conf.default.rp_filter" = true;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.all.log_martians" = true;

        # IPv6 settings
        "net.ipv6.conf.all.forwarding" = cfg.enableIPv6;
        "net.ipv6.conf.all.accept_ra" = 0;
        "net.ipv6.conf.all.autoconf" = 0;
        "net.ipv6.conf.all.use_tempaddr" = 0;
        "net.ipv6.conf.all.accept_redirects" = 0;
        "net.ipv6.conf.${cfg.wanInterface}.accept_ra" = mkIf cfg.enableIPv6 2;
        "net.ipv6.conf.${cfg.wanInterface}.autoconf" = cfg.enableIPv6;
      } // cfg.extraSysctlSettings;
    };

    # Networking configuration
    networking = {
      enableIPv6 = cfg.enableIPv6;

      # Define management VLAN interface
      vlans = let
        vlanInterfaces = listToAttrs (
          map (vlan: {
            name = "${cfg.lanInterface}.${toString vlan.id}";
            value = {
              id = vlan.id;
              interface = cfg.lanInterface;
            };
          }) cfg.vlans
        );
        # Add management VLAN if it's not VLAN 1 (untagged)
        managementVlanInterface = if cfg.managementVlan.id != 1 then {
          "${cfg.lanInterface}.${toString cfg.managementVlan.id}" = {
            id = cfg.managementVlan.id;
            interface = cfg.lanInterface;
          };
        } else {};
      in
        vlanInterfaces // managementVlanInterface;

      nat = {
        enable = true;
        externalInterface = cfg.wanInterface;
        internalInterfaces = 
          # Include base LAN interface if management VLAN is untagged (VLAN 1)
          (if cfg.managementVlan.id == 1 then [ cfg.lanInterface ] else []) ++
          # Include management VLAN interface if it's not untagged
          (if cfg.managementVlan.id != 1 then [ "${cfg.lanInterface}.${toString cfg.managementVlan.id}" ] else []) ++
          # Include all other VLAN interfaces
          (map (vlan: "${cfg.lanInterface}.${toString vlan.id}") cfg.vlans);
        
        internalIPs = 
          [ cfg.managementVlan.network ] ++ 
          (map (vlan: vlan.network) cfg.vlans);
      };

      firewall = {
        allowPing = false;
        extraCommands = concatStringsSep "\n" (
          [
            # Port forwarding rules
            (concatMapStrings (
              rule:
              let
                proto = if rule.protocol == "both" then "" else "-p ${rule.protocol}";
                dport =
                  if rule.destinationPort != null && rule.destinationPort != rule.sourcePort then
                    ":${toString rule.destinationPort}"
                  else
                    "";
              in
              ''
                # Port forwarding: ${toString rule.sourcePort} -> ${rule.destination}${dport}
                iptables -t nat -A PREROUTING -i ${cfg.wanInterface} ${proto} -m ${
                  if rule.protocol == "both" then "tcp" else rule.protocol
                } --dport ${toString rule.sourcePort} -j DNAT --to-destination ${rule.destination}${dport}
              ''
            ) cfg.portForwarding)

            # VLAN isolation rules (if any VLANs are marked as isolated)
          ]
          ++ (flatten (
            map (
              isolatedVlan:
              map (otherVlan: ''
                # Isolate VLAN ${toString isolatedVlan.id} (${isolatedVlan.name}) from VLAN ${toString otherVlan.id} (${otherVlan.name})
                iptables -A FORWARD -i ${cfg.lanInterface}.${toString isolatedVlan.id} -o ${cfg.lanInterface}.${toString otherVlan.id} -j DROP
                iptables -A FORWARD -i ${cfg.lanInterface}.${toString otherVlan.id} -o ${cfg.lanInterface}.${toString isolatedVlan.id} -j DROP
              '') (filter (v: v.id != isolatedVlan.id) cfg.vlans)
            ) (filter (v: v.isolated) cfg.vlans)
          ))

          # VRRP-specific rules
          ++ (optionals cfg.vrrp.enable [
            ''
              # Allow VRRP protocol (protocol 112) between routers
              iptables -A INPUT -p 112 -s ${cfg.vrrp.peerAddress} -j ACCEPT
              iptables -A OUTPUT -p 112 -d ${cfg.vrrp.peerAddress} -j ACCEPT
            ''
          ])
        );
      };

      # Manual configuration of interfaces
      useDHCP = false;

      interfaces = let
        # Determine static IP for management VLAN based on router role
        managementIp = if cfg.routerRole == "primary" 
                       then cfg.managementVlan.primaryIp 
                       else cfg.managementVlan.backupIp;
        
        # Get prefix length for management network
        mgmtPrefixLength = toInt (
          elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" cfg.managementVlan.network) 1
        );
                       
        # Base interfaces configuration
        baseInterfaces = {
          # WAN interface config
          "${cfg.wanInterface}" = 
            if (cfg.externalStaticIp != null) then {
              ipv4.addresses = [{
                address = cfg.externalStaticIp.address;
                prefixLength = cfg.externalStaticIp.prefixLength;
              }];
            } else {
              useDHCP = true;
            };
            
          # Management interface config (either on base LAN or tagged VLAN)
          "${cfg.lanInterface}" = if cfg.managementVlan.id == 1 then {
            ipv4.addresses = [{
              address = managementIp;
              prefixLength = mgmtPrefixLength;
            }];
          } else {};
        };
        
        # Management VLAN interface (if not on base LAN)
        mgmtVlanInterface = if cfg.managementVlan.id != 1 then {
          "${cfg.lanInterface}.${toString cfg.managementVlan.id}" = {
            ipv4.addresses = [{
              address = managementIp;
              prefixLength = mgmtPrefixLength;
            }];
          };
        } else {};
        
        # Other VLAN interfaces
        vlanInterfaces = listToAttrs (
          map (vlan: {
            name = "${cfg.lanInterface}.${toString vlan.id}";
            value = {
              ipv4.addresses = [{
                address = if cfg.routerRole == "primary" then vlan.primaryIp else vlan.backupIp;
                prefixLength = toInt (
                  elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" vlan.network) 1
                );
              }];
            };
          }) cfg.vlans
        );
      in
        baseInterfaces // mgmtVlanInterface // vlanInterfaces;

      defaultGateway = mkIf (cfg.externalStaticIp != null) {
        address = cfg.externalStaticIp.gateway;
        interface = cfg.wanInterface;
      };
    };

    # DNS and DHCP services
    services = {
      # DNS service
      dnsmasq = {
        enable = true;
        servers = cfg.dnsServers;
        extraConfig = let
          # Basic interface configuration
          baseLan = if cfg.managementVlan.id == 1 then "interface = ${cfg.lanInterface}\n" else "";
          mgmtVlan = if cfg.managementVlan.id != 1 
                      then "interface = ${cfg.lanInterface}.${toString cfg.managementVlan.id}\n" 
                      else "";
          otherVlans = concatMapStrings (vlan: 
            "interface = ${cfg.lanInterface}.${toString vlan.id}\n"
          ) cfg.vlans;
  
          # Base configuration
          baseConfig = ''
            bind-interfaces
            ${baseLan}${mgmtVlan}${otherVlans}
          '';
  
          # DHCP relay configuration (only if external DHCP is enabled)
          relayConfig = if (cfg.dhcpMode == "external" && cfg.externalDhcpServer != null)
            then ''
              # Don't function as a DNS server
              port=0
      
              # Log lots of extra information about DHCP transactions
              log-dhcp
      
              # Configure as DHCP relay
              dhcp-relay=${cfg.externalDhcpServer},${cfg.lanInterface}
              ${concatMapStrings (vlan: 
                "dhcp-relay=${cfg.externalDhcpServer},${cfg.lanInterface}.${toString vlan.id}\n"
              ) (filter (vlan: vlan.enableDhcp) cfg.vlans)}
            ''
            else "";
        in
          baseConfig + relayConfig;
      };
    };

      # DHCP service configuration
      dhcpd4 = {
        enable = cfg.dhcpMode == "internal";
        interfaces = 
          # Include base LAN if management is on VLAN 1
          (if cfg.managementVlan.id == 1 then [ cfg.lanInterface ] else []) ++
          # Include all VLAN interfaces that have DHCP enabled
          (map (vlan: "${cfg.lanInterface}.${toString vlan.id}") 
            (filter (vlan: vlan.enableDhcp) cfg.vlans));
        
        extraConfig = let
          # Helper function to calculate netmask from CIDR
          calculateNetmask = cidr: let
            prefix = toInt (
              elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" cidr) 1
            );
            netmaskBits = foldl (a: _: a + "1") "" (range 1 prefix) + 
                         foldl (a: _: a + "0") "" (range 1 (32 - prefix));
            octetBinary = i: substring (i * 8) 8 netmaskBits;
            octetDecimal = i: toString (toInt (octetBinary i));
          in
            "${octetDecimal 0}.${octetDecimal 1}.${octetDecimal 2}.${octetDecimal 3}";
          
          # Generate DHCP config for management network (if using DHCP)
          managementNetworkConfig = let
            network = elemAt (
              builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})\\.([0-9]{1,3})/([0-9]{1,2})$" 
              cfg.managementVlan.network
            ) 0;
            netmask = calculateNetmask cfg.managementVlan.network;
            broadcast = "${network}.255";
            interface = if cfg.managementVlan.id == 1 
                        then cfg.lanInterface 
                        else "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
          in
            if cfg.managementVlan.id == 1 then ''
              subnet ${network}.0 netmask ${netmask} {
                authoritative;
                option domain-name-servers ${concatStringsSep ", " ([ cfg.managementVlan.virtualIp ] ++ cfg.dnsServers)};
                option subnet-mask ${netmask};
                option broadcast-address ${broadcast};
                option routers ${cfg.managementVlan.virtualIp};
                interface ${interface};
                range ${cfg.dhcpRangeStart} ${cfg.dhcpRangeEnd};
              }
            '' else "";

          # Generate DHCP config for each VLAN
          vlanConfigs = concatMapStrings (
            vlan: let
              network = elemAt (
                builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})\\.([0-9]{1,3})/([0-9]{1,2})$" 
                vlan.network
              ) 0;
              netmask = calculateNetmask vlan.network;
              broadcast = "${network}.255";
              interface = "${cfg.lanInterface}.${toString vlan.id}";
            in
              if vlan.enableDhcp then ''
                subnet ${network}.0 netmask ${netmask} {
                  authoritative;
                  option domain-name-servers ${concatStringsSep ", " ([ vlan.virtualIp ] ++ cfg.dnsServers)};
                  option subnet-mask ${netmask};
                  option broadcast-address ${broadcast};
                  option routers ${vlan.virtualIp};
                  interface ${interface};
                  range ${vlan.dhcpRangeStart} ${vlan.dhcpRangeEnd};
                }
              '' else ""
          ) cfg.vlans;
        in
          managementNetworkConfig + vlanConfigs;
      };

      # Keepalived for VRRP
      keepalived = mkIf cfg.vrrp.enable {
        enable = true;
        vrrpInstances = {
          VRRPInstance = {
            interface = if cfg.managementVlan.id == 1 
                       then cfg.lanInterface 
                       else "${cfg.lanInterface}.${toString cfg.managementVlan.id}";
            priority = cfg.vrrp.priority;
            state = if cfg.routerRole == "primary" then "MASTER" else "BACKUP";
            virtualRouterId = cfg.vrrp.routerId;

            extraConfig = ''
              advert_int 1
              authentication {
                auth_type PASS
                auth_pass ${cfg.vrrp.authPass}
              }

              ${optionalString (cfg.vrrp.notifyMaster != null) "notify_master ${cfg.vrrp.notifyMaster}"}
              ${optionalString (cfg.vrrp.notifyBackup != null) "notify_backup ${cfg.vrrp.notifyBackup}"}

              virtual_ipaddress {
                # Management VLAN virtual IP
                ${cfg.managementVlan.virtualIp} dev ${
                  if cfg.managementVlan.id == 1 
                  then cfg.lanInterface 
                  else "${cfg.lanInterface}.${toString cfg.managementVlan.id}"
                }
                
                # Other VLAN virtual IPs
                ${concatMapStrings (vlan: 
                  "${vlan.virtualIp} dev ${cfg.lanInterface}.${toString vlan.id}\n"
                ) cfg.vlans}
              }
            '';
          };
        };
      };

    # Install extra packages required for VLANs and VRRP
    environment.systemPackages = with pkgs; [
      vlan
      iproute2
      iptables
      tcpdump # Useful for debugging network issues
      bridge-utils
      ethtool  # Useful for interface diagnostics
    ];

    # Recommended: journald settings for a router
    services.journald = {
      rateLimitBurst = 0;
      extraConfig = "SystemMaxUse=50M";
    };
  };
}
