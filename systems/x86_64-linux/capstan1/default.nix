{ lib, namespace, ... }:
with lib.${namespace};
{
  # ${namespace} = {
  #   capstan = {
  #     enable = true;
  #     hostname = "capstan1";
  #     ipAddress = "172.16.1.51/24";
  #     bcacheDisks = [ "/dev/sda" "/dev/sdb" ]; # Only define for first node
  #   };
    
  # };

  # # Node-specific overrides
  # projectinitiative.system.extra-monitoring = enabled;
  
  # # First node special configuration
  # services.proxmox-ve.enable = true; # Example special service
}
