{ config, lib, namespace, ... }:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.capstan;
in {
  options.${namespace}.hosts.capstan = {
    enable = mkBoolOpt false "Whether to enable base capstan server configuration";
    hostname = mkOpt types.str "" "Hostname for the server";
    ipAddress = mkOpt types.str "" "Static IP address with CIDR";
    gateway = mkOpt types.str "172.16.1.1" "Default gateway";
    bcachefsRoot = {
      enable = mkBoolOpt false "Enable bcachefs mirror configuration";
      disks = mkOpt (types.listOf types.str) [ ] "Disks for bcachefs array";
      encrypted = mkBoolOpt false "Enable LUKS encryption";
    };
    bcachefs = {
      enable = mkBoolOpt false "Enable bcachefs mirror configuration";
      disks = mkOpt (types.listOf types.str) [ ] "Disks for bcachefs array";
      encrypted = mkBoolOpt false "Enable LUKS encryption";
    };
  };

  config = mkIf cfg.enable {
    networking.hostName = cfg.hostname;
    
    projectinitiative = {
      system = {
        # Enable common base modules
        console-info.ip-display = enabled;
      };
      
      services = {
        ssh-server = enabled;
        ntp-client = enabled;
      };
    };

    disko.devices = mkIf cfg.bcachefsRoot.enable (lib.disko.mkBcachefsMirror {
      disks = cfg.bcachefsRoot.disks;
      encryption = cfg.bcachefsRoot.encrypted;
    });

    # Common network configuration
    networking.interfaces.ens1 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = lib.removeSuffix "/24" cfg.ipAddress;
        prefixLength = 24;
      }];
    };
    networking.defaultGateway = cfg.gateway;

    # Common packages
    environment.systemPackages = with pkgs; [
      bcachefs-tools
      smartmontools
      mlx-eth-tools # For Mellanox cards
    ];

    # Base Kubernetes prep
    services.containerd.enable = true;
    virtualisation.docker.enable = false;
  };
}
