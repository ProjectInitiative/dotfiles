{
  config,
  lib,
  namespace,
  options,
  ...
}:
let
  mountpoint = "/mnt/pool";
in
with lib.${namespace};
{
  disko.devices = {
    disk = {
      nvme1 = {
        type = "disk";
        device = "/dev/disk/by-id/";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "nvme.nvme1";
        };
      };
      ssd1 = {
        type = "disk";
        device = "/dev/disk/by-id/";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "ssd.ssd1";
        };
      };
      hdd1 = {
        type = "disk";
        device = "/dev/disk/by-id/";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "hdd.hdd1";
        };
      };
      hdd2 = {
        type = "disk";
        device = "/dev/disk/by-id/";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "hdd.hdd2";
        };
      };
      hdd3 = {
        type = "disk";
        device = "/dev/disk/by-id/";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "hdd.hdd3";
        };
      };
    };

    bcachefs = {
      pool = {
        type = "bcachefs";
        mountpoint = mountpoint;
        formatOptions = [ "--compression=lz4" ];
        mountOptions = [
          "verbose"
          "degraded"
        ];
      };
    };
  };

  ${namespace} = {
    disko.mdadm-root = {
      enable = true;
      mirroredDrives = [
        "/dev/disk/by-id/"
        "/dev/disk/by-id/"
      ];
    };

    hosts.capstan = {
      enable = true;
      ipAddress = "${config.sensitiveNotSecret.default_subnet}51/24";
      interface = "enp3s0";
      bcachefsInitDevice = "/dev/disk/by-id/";
      mountpoint = mountpoint;
    };

  };

}
