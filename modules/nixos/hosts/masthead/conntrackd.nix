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
in
{
  config = mkIf cfg.enable {
    environment.etc."conntrackd/conntrackd.conf".text = ''
      Sync {
        Mode FULL
        Multicast {
          IPv4 225.0.0.50
          Interface ${cfg.interfaces.sync}
          Group 3780
        }
        Options {
          ExpectationSync {
            Off
          }
        }
      }

      General {
        Nice -1
        HashSize 32768
        HashLimit 131072
        LogFile on
        LockFile /var/lock/conntrack.lock
        Unix {
          Path /var/run/conntrackd.ctl
          Backlog 20
        }
        NetlinkBufferSize 262142
        NetlinkBufferSizeMax 262142
        Filter From Kernelspace {
          Protocol Accept {
            TCP
            UDP
            ICMP
          }
          Address Ignore {
            IPv4_address 127.0.0.1
            IPv4_address ${cfg.management.primaryIp}
            IPv4_address ${cfg.management.backupIp}
            IPv4_address ${cfg.management.virtualIp}
          }
        }
      }
    '';

    systemd.services.conntrackd = {
      description = "Netfilter Connection Tracking State Sync Daemon";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "forking";
        ExecStart = "${pkgs.conntrack-tools}/sbin/conntrackd -d";
        ExecReload = "${pkgs.conntrack-tools}/sbin/conntrackd -R";
        ExecStop = "${pkgs.conntrack-tools}/sbin/conntrackd -k";
        PIDFile = "/var/run/conntrackd.pid";
        Restart = "on-failure";
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];
        AmbientCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];
      };
    };

    boot.kernelModules = [
      "nf_conntrack"
      "nf_conntrack_ipv4"
      "nf_conntrack_tcp"
      "nf_conntrack_udp"
      "nf_conntrack_icmp"
    ];

    boot.kernel.sysctl."net.netfilter.nf_conntrack_max" = 262144;
  };
}
