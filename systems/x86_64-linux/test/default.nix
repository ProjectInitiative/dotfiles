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

  # "/dev/disk/by-path/virtio-pci-0000:00:0a.0"
  # "/dev/disk/by-path/virtio-pci-0000:00:0b.0"
  # ata-SPCC_Solid_State_Disk_C63807960E6A00247759
  # ata-SATA_SSD_D21090883D04210
  projectinitiative = {
    hosts = {
      # base-vm = enabled;
      capstan = {
        enable = true;
        bcachefsRoot = {
          enable = true;
          disks = [
            "/dev/disk/by-path/virtio-pci-0000:00:0a.0"
            "/dev/disk/by-path/virtio-pci-0000:00:0b.0"
          ];
        };

      };
    };
  };
}
