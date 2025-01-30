{ lib, namespace, ... }:
with lib.${namespace};
{
  ${namespace} = {
    capstan = {
      enable = true;
      hostname = "capstan3";
      ipAddress = "172.16.1.53/24";
      bcachefsRoot = {
        enable = true;
        disks = [
          "/dev/disk/by-id/ata-Lexar_256GB_SSD_MD1803W119789"
          "/dev/disk/by-id/ata-SPCC_Solid_State_Disk_0E7C072A0D5A00048168"
        ];
        encrypted = false;

      };
    };

  };

  # # Node-specific overrides
  # projectinitiative.system.extra-monitoring = enabled;

  # # First node special configuration
  # services.proxmox-ve.enable = true; # Example special service
}
