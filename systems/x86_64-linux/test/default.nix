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
{

  # Basic bcachefs support
  boot.supportedFilesystems = [ "bcachefs" ];
  boot.kernelModules = [ "bcachefs" ];
  # use latest kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  environment.systemPackages = with pkgs; [
    bcachefs-tools
    util-linux
  ];

  # "/dev/disk/by-path/virtio-pci-0000:00:0a.0"
  # "/dev/disk/by-path/virtio-pci-0000:00:0b.0"
  # ata-SPCC_Solid_State_Disk_C63807960E6A00247759
  # ata-SATA_SSD_D21090883D04210
  disko.devices = {
    bcachefs = {
      pool = {
        type = "bcachefs";
        devices = {
          disk1 = {
            type = "disk";
            device = "/dev/vdc";
            label = "fast";
            discard = true;
            dataAllowed = [ "journal" "btree" ];
          };
          disk2 = {
            type = "disk";
            device = "/dev/vdd";
            label = "slow";
            durability = 2;
            dataAllowed = [ "user" ];
          };
          disk3 = {
            type = "disk";
            device = "/dev/vde";
            label = "slow";
            durability = 2;
            dataAllowed = [ "user" ];
          };
        };
        formatOptions = [
          "--compression=lz4"
          "--background_target=slow"
          "--foreground_target=fast"
        ];
        mountpoint = "/mnt/pool";
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
        ipAddress = "172.16.1.52/24";

      };
    };
  };
}
