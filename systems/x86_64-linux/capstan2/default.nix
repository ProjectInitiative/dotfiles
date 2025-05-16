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
        "/dev/disk/by-id/ata-SATA_SSD_D21090883D04210"
        "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_C63807960E6A00247759"
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

  disko.devices = {
    disk = {
      nvme1 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-TEAM_TM8FPD002T_TPBF2310170080202273";
        content = {
          type = "gpt";
          partitions = {
            nvme1_1 = {
              # You can name this partition descriptively
              size = "100%";
              content = {
                type = "bcachefs";
                filesystem = "pool"; # Refers to the bcachefs_filesystem defined below
                label = "nvme.nvme1"; # Original label for bcachefs device
              };
            };
          };
        };
      };

      ssd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_2020080207164";
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
        device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2EKC1";
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
        device = "/dev/disk/by-id/ata-ST6000DM003-2CY186_ZCT2EKG5";
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
        device = "/dev/disk/by-id/ata-ST6000NM0115-1YZ110_ZADABZCR";
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
        # This name ("pool") links the partitions above to this definition
        type = "bcachefs_filesystem";
        mountpoint = mountpoint; # Preserving the variable reference from your source
        # Global format options for the bcachefs filesystem
        extraFormatArgs = [
          "--compression=lz4"
          "--foreground_target=nvme" # These targets refer to the labels (e.g., "nvme.nvme1" will match "nvme")
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
        # Since your original config doesn't specify subvolumes for the pool,
        # we assume the entire filesystem is mounted at `mountpoint`.
        # If you need specific subvolumes, you would define them here, similar to the example:
        # subvolumes = {
        #   "subvolumes/root" = { mountpoint = "/"; };
        #   # ... other subvolumes
        # };
      };
    };
  };

}
