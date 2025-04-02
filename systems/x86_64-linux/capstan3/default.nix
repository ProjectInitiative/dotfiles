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

  ${namespace} = {
    disko.mdadm-root = {
      enable = true;
      mirroredDrives = [
        "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_0E7C072A0D5A00048168"
        "/dev/disk/by-id/ata-Lexar_256GB_SSD_MD1803W119789"
      ];
    };

    system = {
      bcachefs-kernel = {
        enable = true;
        branch = "master"; # Or specify a specific commit hash
        sourceHash = "sha256-ulv5deF1YFyDEN8q3UuoeUgfimy+AnsfGnsTNuZYxCM=";
        debug = true;
      };
      bcachefs-module = {
        enable = false;
        rev = "master"; # Or specify a specific commit hash
        hash = "sha256-ulv5deF1YFyDEN8q3UuoeUgfimy+AnsfGnsTNuZYxCM=";
        debug = true;
      };
    };

    hosts.capstan = {
      enable = true;
      ipAddress = "${config.sensitiveNotSecret.default_subnet}53/24";
      interface = "enp3s0";
      enableMlx = true;
      mlxIpAddress = "172.16.4.53";
      mlxPcie = "0000:05:00.0";
      bondMembers = [
        "enp5s0"
        "enp5s0d1"
      ];
      bcachefsInitDevice = "/dev/disk/by-id/nvme-TEAM_TM8FPD002T_TPBF2310170080200016";
      mountpoint = mountpoint;
      k8sServerAddr = "https://172.16.1.45:6443";
    };

  };

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


}
