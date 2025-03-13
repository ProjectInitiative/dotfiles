{
  lib,
  pkgs,
  inputs,
  namespace,
  config,
  options,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
let
  mountpoint = "/mnt/pool";
in
{
  # "/dev/disk/by-path/virtio-pci-0000:00:0a.0"
  # "/dev/disk/by-path/virtio-pci-0000:00:0b.0"
  # ata-SPCC_Solid_State_Disk_C63807960E6A00247759
  # ata-SATA_SSD_D21090883D04210
  disko.devices = {
    disk = {
      bcachefsdisk1 = {
        type = "disk";
        device = "/dev/vdc";
        content = {
          type = "gpt";
          partitions = {
            bcachefs = {
              size = "100%";
              content = {
                type = "bcachefs_member";
                pool = "pool1";
                label = "fast";
                discard = true;
                dataAllowed = [
                  "journal"
                  "btree"
                ];
              };
            };
          };
        };
      };
      bcachefsdisk2 = {
        type = "disk";
        device = "/dev/vdd";
        content = {
          type = "gpt";
          partitions = {
            bcachefs = {
              size = "100%";
              content = {
                type = "bcachefs_member";
                pool = "pool1";
                label = "slow";
                durability = 2;
                dataAllowed = [ "user" ];
              };
            };
          };
        };
      };
      # bcachefsdisk3 = {
      #   type = "disk";
      #   device = "/dev/vde";
      #   content = {
      #     type = "gpt";
      #     partitions = {
      #       bcachefs = {
      #         size = "100%";
      #         content = {
      #           type = "bcachefs_member";
      #           pool = "pool1";
      #           label = "slow";
      #           durability = 2;
      #           dataAllowed = [ "user" ];
      #         };
      #       };
      #     };
      #   };
      # };
      # use whole disk, ignore partitioning
      disk3 = {
        type = "disk";
        device = "/dev/vde";
        content = {
          type = "bcachefs_member";
          pool = "pool1";
          label = "main";
        };
      };
    };

    bcachefs = {
      pool1 = {
        type = "bcachefs";
        mountpoint = mountpoint;
        formatOptions = [
          "--compression=lz4"
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

  systemd.network.links."10-mngmt-mask" = {
    matchConfig = {
      MACAddress = "BC:24:11:07:94:55";
    };
    linkConfig = {
      Name = "enp3s0";
    };
  };

  systemd.network.links."10-mlx" = {
    matchConfig = {
      MACAddress = "BC:24:11:A5:4C:81";
    };
    linkConfig = {
      Name = "bond0";
    };
  };

  networking = {
    # Interface configuration
    interfaces = {
      ens19 = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "172.16.4.45";
            prefixLength = 24;
          }
        ];
      };
    };
  };

  projectinitiative = {

    disko.mdadm-root = {
      enable = true;
      mirroredDrives = [
        # "/dev/disk/by-path/virtio-pci-0000:00:0a.0"
        # "/dev/disk/by-path/virtio-pci-0000:00:0b.0"
        # "/dev/sda"
        # "/dev/sdb"
        "/dev/vda"
        "/dev/vdb"
      ];
    };

    hosts = {
      # base-vm = enabled;
      capstan = {
        enable = true;
        ipAddress = "172.16.1.45/24";
        interface = "enp3s0";
        bcachefsInitDevice = "/dev/vdc1";
        mountpoint = mountpoint;
        isFirstK8sNode = true;
      };
    };
  };
}
