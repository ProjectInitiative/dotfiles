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
        device = "/dev/disk/by-id/nvme-TEAM_TM8FPD002T_TPBF2310170080200016";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "nvme.nvme1";
        };
      };
      ssd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_AA000000000000000101";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "ssd.ssd1";
        };
      };
      hdd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2DSW5";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "hdd.hdd1";
        };
      };
      hdd2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2EMGM";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "hdd.hdd2";
        };
      };
      hdd3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST6000NM0115-1YZ110_ZADABZPK";
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
        formatOptions = [
          "--compression=lz4"
        ];
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
        "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_0E7C072A0D5A00048168"
        "/dev/disk/by-id/ata-Lexar_256GB_SSD_MD1803W119789"
      ];
    };

    hosts.capstan = {
      enable = true;
      ipAddress = "${config.sensitiveNotSecret.default_subnet}53/24";
      interface = "enp3s0";
      bcachefsInitDevice = "/dev/disk/by-id/nvme-TEAM_TM8FPD002T_TPBF2310170080200016";
      mountpoint = mountpoint;
      k8sServerAddr = "https://172.16.1.45:6443";
    };

  };

}
