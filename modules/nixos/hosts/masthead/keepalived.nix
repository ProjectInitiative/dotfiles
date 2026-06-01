{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.masthead;
  isPrimary = cfg.routerRole == "primary";
  isBackup = !isPrimary;

  mgmtInterfaceName =
    if cfg.management.vlanId == 1 then
      cfg.interfaces.lan
    else
      "${cfg.interfaces.lan}.${toString cfg.management.vlanId}";

  peerIp = if isPrimary then cfg.management.backupIp else cfg.management.primaryIp;

  parsePrefix = cidr: toInt (builtins.elemAt (builtins.split "/" cidr) 2);

  mkVlanVrrpInstance = vlan: idx: {
    name = "VI_VLAN_${vlan.name}";
    value = {
      virtualRouterId = cfg.vrrp.virtualRouterIdBase + idx;
      priority = if isPrimary then cfg.vrrp.priority.primary else cfg.vrrp.priority.backup;
      interface = "${cfg.interfaces.lan}.${toString vlan.id}";
      useVmac = false;
      advertisementInterval = 1;
      authPassFile = cfg.vrrp.authPassFile;
      virtualIPs = [
        {
          address = vlan.virtualIp;
          prefixLength = parsePrefix vlan.network;
        }
      ];
      trackInterfaces = [
        cfg.interfaces.sync
        cfg.interfaces.wan
      ];
      notifyMaster = "/etc/masthead/openflow-master.sh";
      notifyBackup = "/etc/masthead/openflow-backup.sh";
      notifyFault = "/etc/masthead/openflow-fault.sh";
    };
  };
in
{
  config = mkIf (cfg.enable && cfg.vrrp.enable) {
    networking.vrrp = {
      enable = true;
      globalDefs.routerId = config.networking.hostName;

      vrrpInstances = {
        VI_MGMT = {
          virtualRouterId = cfg.vrrp.virtualRouterIdBase;
          priority = if isPrimary then cfg.vrrp.priority.primary else cfg.vrrp.priority.backup;
          interface = mgmtInterfaceName;
          useVmac = false;
          advertisementInterval = 1;
          virtualIPs = [
            {
              address = cfg.management.virtualIp;
              prefixLength = parsePrefix cfg.management.network;
            }
          ];
        };
      };
    };

    # ── Notify Scripts ────────────────────────────────────────────
    systemd.tmpfiles.rules = [ "d /var/log/masthead 0750 root root" ];

    environment.etc."masthead/openflow-master.sh" = {
      mode = "0755";
      text = ''
        #!/run/current-system/sw/bin/bash
        # Flush conntrackd state into kernel on promotion
        ${pkgs.conntrack-tools}/sbin/conntrackd -f 2>/dev/null || true
        ${pkgs.conntrack-tools}/sbin/conntrackd -R 2>/dev/null || true

        logger -t masthead-openflow "MASTER: conntrackd flushed, claims VIP and OpenFlow virtual wire"
      '';
    };

    environment.etc."masthead/openflow-backup.sh" = {
      mode = "0755";
      text = ''
        #!/run/current-system/sw/bin/bash
        logger -t masthead-openflow "BACKUP: This node is now standby"
      '';
    };

    environment.etc."masthead/openflow-fault.sh" = {
      mode = "0755";
      text = ''
        #!/run/current-system/sw/bin/bash
        logger -t masthead-openflow "FAULT: VRRP fault detected"
      '';
    };

    # ── Firewall Rules for HA protocols ───────────────────────────
    networking.firewall.extraCommands = ''
      # Allow VRRP (protocol 112) on sync interface
      iptables -A INPUT -i ${cfg.interfaces.sync} -p 112 -j ACCEPT
      iptables -A OUTPUT -o ${cfg.interfaces.sync} -p 112 -j ACCEPT

      # Allow conntrackd multicast sync
      iptables -A INPUT -i ${cfg.interfaces.sync} -d 225.0.0.50 -j ACCEPT
      iptables -A OUTPUT -o ${cfg.interfaces.sync} -d 225.0.0.50 -j ACCEPT

      # Allow Kea DHCP HA failover
      iptables -A INPUT -i ${mgmtInterfaceName} -p tcp --dport ${toString cfg.vrrp.keaFailoverPort} -s ${peerIp} -j ACCEPT
    '';
  };
}
