{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;
let
  cfg = config.${namespace}.hosts.masthead;
  priority = if cfg.role == "primary" then 255 else 100;
in
{
  config = mkIf cfg.enable {
    networking.vrrp.enable = true;

    networking.vrrp.vrrpInstances = {
      lan0 = {
        virtualRouterId = 20;
        priority = priority;
        interface = "lan0";
        virtualIPs = [
          {
            address = cfg.lanVip;
            prefixLength = 24;
          }
        ];
        notifyMaster = "${pkgs.writeShellScript "notify-master-lan0" ''
          ${pkgs.iproute2}/bin/ip link set dev wan0 address ${cfg.wanMac}
          ${pkgs.iproute2}/bin/ip link set dev wan0 up
          ${lib.optionalString cfg.qos.enable "${cfg.qos.applyScript} ${cfg.role}"}
        ''}";
        notifyBackup = "${pkgs.writeShellScript "notify-backup-lan0" ''
          ${pkgs.iproute2}/bin/ip link set dev wan0 down
          ${lib.optionalString cfg.qos.enable "${cfg.qos.removeScript}"}
        ''}";
      };
      vlan10 = {
        virtualRouterId = 30;
        priority = priority;
        interface = "vlan10";
        virtualIPs = [
          {
            address = cfg.vlan10Vip;
            prefixLength = 24;
          }
        ];
      };
      vlan21 = {
        virtualRouterId = 40;
        priority = priority;
        interface = "vlan21";
        virtualIPs = [
          {
            address = cfg.vlan21Vip;
            prefixLength = 24;
          }
        ];
      };
      vlan22 = {
        virtualRouterId = 50;
        priority = priority;
        interface = "vlan22";
        virtualIPs = [
          {
            address = cfg.vlan22Vip;
            prefixLength = 24;
          }
        ];
      };
      vlan30 = {
        virtualRouterId = 60;
        priority = priority;
        interface = "vlan30";
        virtualIPs = [
          {
            address = cfg.vlan30Vip;
            prefixLength = 24;
          }
        ];
      };
    };
  };
}
