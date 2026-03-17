{
  options,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.masthead;
in
{
  options.${namespace}.hosts.masthead = with types; {
    enable = mkBoolOpt false "Whether or not to enable the masthead router base config.";
    role = mkOption {
      type = types.enum [
        "primary"
        "backup"
      ];
      description = "Role of this router (primary or backup)";
      default = "primary";
    };
  };

  config = mkIf cfg.enable {
    networking = {
      useDHCP = false;
      bridges = {
        br0 = {
          interfaces = [ ];
        };
      };
      vlans = {
        vlan10 = {
          id = 10;
          interface = "br0";
        };
      };
    };
    services.kea = {
      dhcp4 = {
        enable = true;
        settings = {
          interfaces-config = {
            interfaces = [ "vlan10" ];
          };
          subnet4 = [ ];
        };
      };
    };
    services.dnsmasq = {
      enable = true;
    };
  };
}
