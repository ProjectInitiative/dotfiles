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

    suites = {
      attic = {
        enableServer = true;
      };
    };

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
        rev = "0fb34e7b933ae01cf5789b91812fc75b82ff3a5d";
        hash = "sha256-jbVpXfZaNVFyn4BlkFLYERLUpCVrB6ybVPg6szdLZCo=";
        debug = true;
      };
      bcachefs-module = {
        enable = false;
        rev = ""; # Or specify a specific commit hash
        hash = "";
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
      k8sServerAddr = "https://172.16.1.52:6443";
    };

  };

  disko.devices = {
    disk = {
      nvme1 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-TEAM_TM8FPD002T_TPBF2310170080200016";
        content = {
          type = "gpt";
          partitions = {
            nvme1_1 = {
              # Partition name (can be customized)
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "pool"; # Links to the definition below
                label = "nvme.nvme1"; # bcachefs device label
              };
            };
          };
        };
      };

      ssd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_AA000000000000000101";
        content = {
          type = "gpt";
          partitions = {
            ssd1_1 = {
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "pool";
                label = "ssd.ssd1";
              };
            };
          };
        };
      };

      hdd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2DSW5";
        content = {
          type = "gpt";
          partitions = {
            hdd1_1 = {
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "pool";
                label = "hdd.hdd1";
              };
            };
          };
        };
      };

      hdd2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2EMGM";
        content = {
          type = "gpt";
          partitions = {
            hdd2_1 = {
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "pool";
                label = "hdd.hdd2";
              };
            };
          };
        };
      };

      hdd3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST6000NM0115-1YZ110_ZADABZPK";
        content = {
          type = "gpt";
          partitions = {
            hdd3_1 = {
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "pool";
                label = "hdd.hdd3";
              };
            };
          };
        };
      };
    };

    bcachefs_filesystems = {
      pool = {
        # This name ("pool") is referenced by the partitions above
        type = "bcachefs_filesystem";
        mountpoint = mountpoint; # Preserving your variable reference
        # These are the global formatting options for the bcachefs filesystem
        extraFormatArgs = [
          "--compression=lz4"
          "--foreground_target=nvme" # Targets refer to device labels (e.g., "nvme.nvme1" matches "nvme")
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
        # If you don't define subvolumes here, the entire filesystem is typically
        # mounted at the 'mountpoint'. If you need specific subvolumes, add them like:
        # subvolumes = {
        #   "subvolumes/data" = { mountpoint = "/data"; };
        # };
      };
    };
  };

}
