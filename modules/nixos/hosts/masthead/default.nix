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
  cfg = config.${namespace}.hosts.masthead;
  sops = config.sops;
in
{
  options.${namespace}.hosts.masthead = with types; {
    enable = mkBoolOpt false "Whether or not to enable the masthead router base config.";

    externalInterface = mkOption {
      type = types.str;
      description = "The network interface connected to the internet/WAN";
      example = "enp1s0";
    };

    internalInterface = mkOption {
      type = types.str;
      description = "The network interface connected to the internal network/LAN";
      example = "enp2s0";
    };

    internalNetwork = mkOption {
      type = types.str;
      description = "The internal network in CIDR notation";
      example = "192.168.1.0/24";
      default = "192.168.1.0/24";
    };

    internalIpAddress = mkOption {
      type = types.str;
      description = "The IP address of the router on the internal network";
      example = "192.168.1.1";
      default = "192.168.1.1";
    };

    dhcpRangeStart = mkOption {
      type = types.str;
      description = "The start of the DHCP range";
      example = "192.168.1.100";
      default = "192.168.1.100";
    };

    dhcpRangeEnd = mkOption {
      type = types.str;
      description = "The end of the DHCP range";
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

    # New VLAN options
    vlans = mkOption {
      type = types.listOf (types.submodule {
        options = {
          id = mkOption {
            type = types.int;
            description = "VLAN ID";
            example = 10;
          };
          
          name = mkOption {
            type = types.str;
            description = "VLAN name";
            example = "iot";
          };
          
          network = mkOption {
            type = types.str;
            description = "VLAN network in CIDR notation";
            example = "192.168.10.0/24";
          };
          
          ipAddress = mkOption {
            type = types.str;
            description = "Router's IP address on this VLAN";
            example = "192.168.10.1";
          };
          
          enableDhcp = mkOption {
            type = types.bool;
            description = "Whether to enable DHCP on this VLAN";
            default = true;
          };
          
          dhcpRangeStart = mkOption {
            type = types.str;
            description = "The start of the DHCP range for this VLAN";
            example = "192.168.10.100";
          };
          
          dhcpRangeEnd = mkOption {
            type = types.str;
            description = "The end of the DHCP range for this VLAN";
            example = "192.168.10.250";
          };
          
          isolated = mkOption {
            type = types.bool;
            description = "Whether this VLAN should be isolated from other VLANs";
            default = false;
          };
        };
      });
      description = "List of VLANs to configure";
      default = [];
    };
    
    # VRRP/keepalived configuration
    vrrp = {
      enable = mkOption {
        type = types.bool;
        description = "Whether to enable VRRP for high availability";
        default = false;
      };
      
      routerName = mkOption {
        type = types.enum [ "Topsail" "StormJib" ];
        description = "Name of this router (Topsail for primary, StormJib for backup)";
        example = "Topsail";
      };
      
      routerId = mkOption {
        type = types.int;
        description = "Unique VRRP router ID";
        default = 10;
      };
      
      priority = mkOption {
        type = types.int;
        description = "VRRP priority (higher number = higher priority)";
        example = 100;
      };
      
      authPass = mkOption {
        type = types.str;
        description = "VRRP authentication password";
      };
      
      peerAddress = mkOption {
        type = types.str;
        description = "IP address of the peer router";
        example = "192.168.1.2";
      };
      
      virtualIps = mkOption {
        type = types.listOf (types.submodule {
          options = {
            interface = mkOption {
              type = types.str;
              description = "Interface for the virtual IP";
              example = "enp2s0.10";
            };
            
            address = mkOption {
              type = types.str;
              description = "Virtual IP address";
              example = "192.168.10.1";
            };
          };
        });
        description = "List of virtual IP addresses";
        default = [];
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

    # Extract network details
    _module.args.routerConfig = cfg;

    # Parse the CIDR notation
    assertions = [
      {
        assertion =
          builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" cfg.internalNetwork
          != null;
        message = "internalNetwork must be in valid CIDR notation (e.g., 192.168.1.0/24)";
      }
    ] ++ (map (vlan: {
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
        "net.ipv6.conf.${cfg.externalInterface}.accept_ra" = mkIf cfg.enableIPv6 2;
        "net.ipv6.conf.${cfg.externalInterface}.autoconf" = cfg.enableIPv6;
      } // cfg.extraSysctlSettings;
    };

    # Networking configuration
    networking = {
      enableIPv6 = cfg.enableIPv6;
      
      # Enable VLAN support
      vlans = listToAttrs (map (vlan: {
        name = "${cfg.internalInterface}.${toString vlan.id}";
        value = {
          id = vlan.id;
          interface = cfg.internalInterface;
        };
      }) cfg.vlans);

      nat = {
        enable = true;
        externalInterface = cfg.externalInterface;
        internalInterfaces = [ cfg.internalInterface ] ++ 
                             (map (vlan: "${cfg.internalInterface}.${toString vlan.id}") cfg.vlans);
        internalIPs = [ cfg.internalNetwork ] ++ 
                      (map (vlan: vlan.network) cfg.vlans);
      };

      firewall = {
        allowPing = false;
        extraCommands = concatStringsSep "\n" ([
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
              iptables -t nat -A PREROUTING -i ${cfg.externalInterface} ${proto} -m ${
                if rule.protocol == "both" then "tcp" else rule.protocol
              } --dport ${toString rule.sourcePort} -j DNAT --to-destination ${rule.destination}${dport}
            ''
          ) cfg.portForwarding)
          
          # VLAN isolation rules (if any VLANs are marked as isolated)
        ] ++ (flatten (map (
            isolatedVlan: map (
              otherVlan: ''
                # Isolate VLAN ${toString isolatedVlan.id} (${isolatedVlan.name}) from VLAN ${toString otherVlan.id} (${otherVlan.name})
                iptables -A FORWARD -i ${cfg.internalInterface}.${toString isolatedVlan.id} -o ${cfg.internalInterface}.${toString otherVlan.id} -j DROP
                iptables -A FORWARD -i ${cfg.internalInterface}.${toString otherVlan.id} -o ${cfg.internalInterface}.${toString isolatedVlan.id} -j DROP
              ''
            ) (filter (v: v.id != isolatedVlan.id) cfg.vlans)
          ) (filter (v: v.isolated) cfg.vlans)))
          
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

      interfaces = listToAttrs ([
        # External interface config
        {
          name = cfg.externalInterface;
          value = if (cfg.externalStaticIp != null) then {
            ipv4.addresses = [
              {
                address = cfg.externalStaticIp.address;
                prefixLength = cfg.externalStaticIp.prefixLength;
              }
            ];
          } else {
            useDHCP = true;
          };
        }
        
        # Main internal interface config 
        {
          name = cfg.internalInterface;
          value = {
            ipv4.addresses = mkIf (!cfg.vrrp.enable) [
              {
                address = cfg.internalIpAddress;
                prefixLength = elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" cfg.internalNetwork) 1;
              }
            ];
          };
        }
      ] ++ 
      
      # VLAN interface configurations
      (map (vlan: {
        name = "${cfg.internalInterface}.${toString vlan.id}";
        value = {
          ipv4.addresses = mkIf (!cfg.vrrp.enable) [
            {
              address = vlan.ipAddress;
              prefixLength = elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" vlan.network) 1;
            }
          ];
        };
      }) cfg.vlans));

      defaultGateway = mkIf (cfg.externalStaticIp != null) {
        address = cfg.externalStaticIp.gateway;
        interface = cfg.externalInterface;
      };
    };

    # DNS and DHCP services
    services = {
      # DNS service
      dnsmasq = {
        enable = true;
        servers = cfg.dnsServers;
        extraConfig = ''
          bind-interfaces
          interface = ${cfg.internalInterface}
          ${concatMapStrings (vlan: "interface = ${cfg.internalInterface}.${toString vlan.id}\n") cfg.vlans}
        '';
      };

      # DHCP service for main network
      dhcpd4 = {
        enable = true;
        interfaces = [ cfg.internalInterface ] ++ 
                     (map (vlan: "${cfg.internalInterface}.${toString vlan.id}") 
                      (filter (vlan: vlan.enableDhcp) cfg.vlans));
        extraConfig =
          let
            # Generate DHCP config for main network
            mainNetworkConfig = let
              network = elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})\\.([0-9]{1,3})/([0-9]{1,2})$" cfg.internalNetwork) 0;
              netmask =
                let
                  prefix = toInt (
                    elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" cfg.internalNetwork) 1
                  );
                  netmaskBits =
                    foldl (a: _: a + "1") "" (range 1 prefix) + foldl (a: _: a + "0") "" (range 1 (32 - prefix));
                  octetBinary = i: substring (i * 8) 8 netmaskBits;
                  octetDecimal = i: toString (toInt (octetBinary i));
                in
                "${octetDecimal 0}.${octetDecimal 1}.${octetDecimal 2}.${octetDecimal 3}";
              broadcast = "${network}.255";
              routerIp = if cfg.vrrp.enable 
                         then (findFirst (vip: vip.interface == cfg.internalInterface) 
                              { address = cfg.internalIpAddress; } 
                              cfg.vrrp.virtualIps).address
                         else cfg.internalIpAddress;
            in
            ''
              subnet ${network}.0 netmask ${netmask} {
                authoritative;
                option domain-name-servers ${concatStringsSep ", " ([ routerIp ] ++ cfg.dnsServers)};
                option subnet-mask ${netmask};
                option broadcast-address ${broadcast};
                option routers ${routerIp};
                interface ${cfg.internalInterface};
                range ${cfg.dhcpRangeStart} ${cfg.dhcpRangeEnd};
              }
            '';
            
            # Generate DHCP config for each VLAN
            vlanConfigs = concatMapStrings (
              vlan: 
              let
                network = elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})\\.([0-9]{1,3})/([0-9]{1,2})$" vlan.network) 0;
                prefix = toInt (
                  elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})/([0-9]{1,2})$" vlan.network) 1
                );
                netmaskBits =
                  foldl (a: _: a + "1") "" (range 1 prefix) + foldl (a: _: a + "0") "" (range 1 (32 - prefix));
                octetBinary = i: substring (i * 8) 8 netmaskBits;
                octetDecimal = i: toString (toInt (octetBinary i));
                netmask = "${octetDecimal 0}.${octetDecimal 1}.${octetDecimal 2}.${octetDecimal 3}";
                broadcast = "${network}.255";
                routerIp = if cfg.vrrp.enable 
                           then (findFirst (vip: vip.interface == "${cfg.internalInterface}.${toString vlan.id}") 
                                { address = vlan.ipAddress; } 
                                cfg.vrrp.virtualIps).address
                           else vlan.ipAddress;
              in
              if vlan.enableDhcp then ''
                subnet ${network}.0 netmask ${netmask} {
                  authoritative;
                  option domain-name-servers ${concatStringsSep ", " ([ routerIp ] ++ cfg.dnsServers)};
                  option subnet-mask ${netmask};
                  option broadcast-address ${broadcast};
                  option routers ${routerIp};
                  interface ${cfg.internalInterface}.${toString vlan.id};
                  range ${vlan.dhcpRangeStart} ${vlan.dhcpRangeEnd};
                }
              '' else ""
            ) cfg.vlans;
          in
          mainNetworkConfig + vlanConfigs;
      };
      
      # Keepalived for VRRP
      keepalived = mkIf cfg.vrrp.enable {
        enable = true;
        vrrpInstances = {
          VRRPMainInstance = {
            interface = cfg.internalInterface;
            priority = cfg.vrrp.priority;
            state = if cfg.vrrp.routerName == "Topsail" then "MASTER" else "BACKUP";
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
                ${concatMapStrings (vip: 
                  "${vip.address} dev ${vip.interface}\n"
                ) cfg.vrrp.virtualIps}
              }
            '';
          };
        };
      };
    };

    # Install extra packages required for VLANs and VRRP
    environment.systemPackages = with pkgs; [
      vlan
      iproute2
      iptables
      tcpdump    # Useful for debugging network issues
      bridge-utils
    ];

    # Recommended: journald settings for a router
    services.journald = {
      rateLimitBurst = 0;
      extraConfig = "SystemMaxUse=50M";
    };

  };
}
