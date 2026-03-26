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
in
{
  config = mkIf cfg.enable {
    environment.etc."conntrackd/conntrackd.conf".text = ''
      Sync {
        Mode FTFW {
          ResendQueueSize 131072
          CommitTimeout 180
          PurgeTimeout 5
          ACKWindowSize 300
          DisableExternalCache Off
        }

        Multicast {
          IPv4_address 225.0.0.50
          IPv4_interface vlan40
          Port 3780
          Group 3780
        }
      }

      General {
        HashSize 32768
        HashLimit 131072
        Syslog on
        LockFile /var/lock/conntrack.lock
        UNIX {
          Path /var/run/conntrackd.ctl
          Backlog 20
        }
        NetlinkBufferSize 2097152
        NetlinkBufferSizeMaxGrowth 8388608
        Filter From Userspace {
          Protocol Accept {
            TCP
            SCTP
            DCCP
          }
          Address Ignore {
            IPv4_address 127.0.0.1
          }
        }
      }
    '';

    systemd.services.conntrackd = {
      description = "Connection tracking state synchronization daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [
        pkgs.conntrack-tools
        pkgs.iproute2
      ];
      serviceConfig = {
        ExecStart = "${pkgs.conntrack-tools}/bin/conntrackd -C /etc/conntrackd/conntrackd.conf";
        Restart = "always";
      };
    };
  };
}
