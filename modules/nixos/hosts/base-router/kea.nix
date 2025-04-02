{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.${mkModuleName "hosts"}.base-router;
  keaConfig = {
    Dhcp4 = {
      interfaces-config = {
        interfaces =
          (mkIf (cfg.managementVlan.id == 1) [ cfg.lanInterface ])
          ++ (map (vlan: "${cfg.lanInterface}.${toString vlan.id}") (
            filter (vlan: vlan.enableDhcp) cfg.vlans
          ));
      };
      subnet4 = flatten (
        (optional (cfg.dhcpMode == "internal") ({
          id = 1; # Arbitrary ID for the base/management VLAN
          subnet = elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})\\.([0-9]{1,3})/([0-9]{1,2})$" cfg.managementVlan.network) 0;
          pools = [ { pool = "${cfg.dhcpRangeStart} - ${cfg.dhcpRangeEnd}"; } ];
          option-data = [
            {
              name = "routers";
              data = cfg.managementVlan.virtualIp;
            }
            {
              name = "domain-name-servers";
              data = concatStringsSep "," cfg.dnsServers;
            }
          ];
        }))
        ++ (map (
          vlan:
          optional (vlan.enableDhcp && cfg.dhcpMode == "internal") {
            id = vlan.id + 100; # Offset VLAN IDs to avoid collision
            subnet = elemAt (builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})\\.([0-9]{1,3})/([0-9]{1,2})$" vlan.network) 0;
            pools = [ { pool = "${vlan.dhcpRangeStart} - ${vlan.dhcpRangeEnd}"; } ];
            option-data = [
              {
                name = "routers";
                data = vlan.virtualIp;
              }
              {
                name = "domain-name-servers";
                data = concatStringsSep "," cfg.dnsServers;
              }
            ];
          }
        ) cfg.vlans)
      );
    };
  };
in
{
  systemd.services.kea-dhcp4-server = {
    enable = cfg.dhcpMode == "internal";
    description = "Kea DHCPv4 Server";
    after = [ "network.target" ];
    requires = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    script = ''
      exec ${pkgs.kea}/bin/kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
    '';
    serviceConfig = {
      User = "kea";
      Group = "kea";
      Restart = "on-failure";
    };
  };

  environment.etc."kea/kea-dhcp4.conf".text = builtins.toJSON {
    Dhcp4 = keaConfig.Dhcp4;
  };

  users.users.kea = {
    group = "kea";
    description = "Kea DHCP Server User";
    system = true;
  };

  users.groups.kea = {
    gid = 333; # Or any other suitable GID
    system = true;
  };

  environment.systemPackages = (config.environment.systemPackages or [ ]) ++ [ pkgs.kea ];
}
