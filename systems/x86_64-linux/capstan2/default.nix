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
        device = "/dev/disk/by-id/nvme-TEAM_TM8FPD002T_TPBF2310170080202273";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "nvme.nvme1";
        };
      };
      ssd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_2020080207164";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "ssd.ssd1";
        };
      };
      hdd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2EKC1";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "hdd.hdd1";
        };
      };
      hdd2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2EKG5";
        content = {
          type = "bcachefs_member";
          pool = "pool";
          label = "hdd.hdd2";
        };
      };
      hdd3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST6000NM0115-1YZ110_ZADABZCR";
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
          "--foreground_target=nvme"
          "--background_target=hdd"
          "--promote_target=ssd"
          "--metadata_replicas=2"
          "--metadata_replicas_required=1"
          "--data_replicas=2"
          "--data_replicas_required=1"
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
        "/dev/disk/by-id/ata-SATA_SSD_D21090883D04210"
        "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_C63807960E6A00247759"
      ];
    };

    hosts.capstan = {
      enable = true;
      ipAddress = "${config.sensitiveNotSecret.default_subnet}52/24";
      interface = "enp3s0";
      enableMlx = true;
      mlxIpAddress = "172.16.4.52";
      mlxPcie = "0000:05:00.0";
      bondMembers = [
        "enp5s0"
        "enp5s0d1"
      ];
      bcachefsInitDevice = "/dev/disk/by-id/nvme-TEAM_TM8FPD002T_TPBF2310170080202273";
      mountpoint = mountpoint;
      k8sServerAddr = "https://172.16.1.45:6443";
    };

  };

}
