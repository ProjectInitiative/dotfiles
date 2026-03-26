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
in
{
  imports = [
    ./vrrp
    ./multi-wan
    ./conntrack
  ];

  options.${namespace}.hosts.masthead = with types; {
    enable = mkBoolOpt false "Whether or not to enable the masthead router base config.";
    role = mkOpt (types.enum [
      "primary"
      "backup"
    ]) "primary" "The role of the masthead router.";
    wanMac = mkOpt types.str "00:00:00:00:00:00" "MAC address for WAN spoofing.";
    wanVip = mkOpt types.str "203.0.113.100" "Virtual IP for WAN interface.";
    lanVip = mkOpt types.str "172.16.1.1" "Virtual IP for LAN interface.";
    vlan10Vip = mkOpt types.str "192.168.10.1" "Virtual IP for VLAN 10.";
    vlan21Vip = mkOpt types.str "192.168.21.1" "Virtual IP for VLAN 21.";
    vlan22Vip = mkOpt types.str "192.168.22.1" "Virtual IP for VLAN 22.";
    vlan30Vip = mkOpt types.str "192.168.30.1" "Virtual IP for VLAN 30.";
    healthCheckIp = mkOpt types.str "8.8.8.8" "IP address for Multi-WAN health check.";
  };

  config = mkIf cfg.enable {
    # Declarative network configurations for interfaces, VLANs, and bridges
    networking.bridges = {
      lan0 = {
        interfaces = [ ];
      };
    };

    networking.interfaces.lan0 = {
      ipv4.addresses = [
        {
          address = if cfg.role == "primary" then "172.16.1.2" else "172.16.1.3";
          prefixLength = 24;
        }
      ];
    };

    networking.interfaces.vlan10 = {
      ipv4.addresses = [
        {
          address = if cfg.role == "primary" then "192.168.10.2" else "192.168.10.3";
          prefixLength = 24;
        }
      ];
    };

    networking.interfaces.vlan21 = {
      ipv4.addresses = [
        {
          address = if cfg.role == "primary" then "192.168.21.2" else "192.168.21.3";
          prefixLength = 24;
        }
      ];
    };

    networking.interfaces.vlan22 = {
      ipv4.addresses = [
        {
          address = if cfg.role == "primary" then "192.168.22.2" else "192.168.22.3";
          prefixLength = 24;
        }
      ];
    };

    networking.interfaces.vlan30 = {
      ipv4.addresses = [
        {
          address = if cfg.role == "primary" then "192.168.30.2" else "192.168.30.3";
          prefixLength = 24;
        }
      ];
    };

    networking.interfaces.vlan40 = {
      ipv4.addresses = [
        {
          address = if cfg.role == "primary" then "169.254.255.1" else "169.254.255.2";
          prefixLength = 24;
        }
      ];
    };

    networking.vlans = {
      vlan1 = {
        id = 1;
        interface = "lan0";
      };
      vlan10 = {
        id = 10;
        interface = "lan0";
      };
      vlan21 = {
        id = 21;
        interface = "lan0";
      };
      vlan22 = {
        id = 22;
        interface = "lan0";
      };
      vlan30 = {
        id = 30;
        interface = "lan0";
      };
      vlan40 = {
        id = 40;
        interface = "lan0";
      };
    };

    # Configure DNS resolvers
    networking.nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];

    # Configure DHCP server using Kea
    services.kea.dhcp4 = {
      enable = true;
      settings = {
        interfaces-config = {
          interfaces = [
            "vlan10"
            "vlan21"
            "vlan22"
            "vlan30"
          ];
        };
        hooks-libraries = [
          {
            library = "${pkgs.kea}/lib/kea/hooks/libdhcp_lease_cmds.so";
          }
          {
            library = "${pkgs.kea}/lib/kea/hooks/libdhcp_ha.so";
            parameters = {
              high-availability = [
                {
                  this-server-name = "router-${cfg.role}";
                  mode = "hot-standby";
                  heartbeat-delay = 10000;
                  max-response-delay = 60000;
                  max-ack-delay = 10000;
                  max-unacked-clients = 5;
                  peers = [
                    {
                      name = "router-primary";
                      url = "http://172.16.1.2:8000/";
                      role = "primary";
                    }
                    {
                      name = "router-backup";
                      url = "http://172.16.1.3:8000/";
                      role = "standby";
                    }
                  ];
                }
              ];
            };
          }
        ];

        subnet4 = [
          {
            subnet = "192.168.10.0/24";
            pools = [ { pool = "192.168.10.100 - 192.168.10.250"; } ];
          }
          {
            subnet = "192.168.21.0/24";
            pools = [ { pool = "192.168.21.100 - 192.168.21.250"; } ];
          }
          {
            subnet = "192.168.22.0/24";
            pools = [ { pool = "192.168.22.100 - 192.168.22.250"; } ];
          }
          {
            subnet = "192.168.30.0/24";
            pools = [ { pool = "192.168.30.100 - 192.168.30.250"; } ];
          }
        ];
      };
    };
  };
}
