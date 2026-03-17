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
  options.${namespace}.hosts.masthead = with types; {
    enable = mkBoolOpt false "Whether or not to enable the masthead router base config.";
    role = mkOpt (types.enum [
      "primary"
      "backup"
    ]) "primary" "The role of the masthead router.";
  };

  config = mkIf cfg.enable {
    # Declarative network configurations for interfaces, VLANs, and bridges
    networking.bridges = {
      lan0 = {
        interfaces = [ ];
      };
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
