{
  config,
  lib,
  pkgs,
  namespace,
  ...
}:
with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.capstan;
in
{
  options.${namespace}.hosts.capstan = {
    enable = mkBoolOpt false "Whether to enable base capstan server configuration";
    # hostname = mkOpt types.str "" "Hostname for the server";
    ipAddress = mkOpt types.str "" "Static IP address with CIDR";
    interface = mkOpt types.str "" "Static IP Interface";
    gateway = mkOpt types.str "" "Default gateway";
    bcachefsInitDevice = mkOpt types.str "" "Device path for one of the bcachefs pool drives";
    mountpoint = mkOpt types.str "/mnt/pool" "Path to mount bcachefs pool";
  };

  config = mkIf cfg.enable {
    # enable custom secrets
    sops.secrets = mkMerge [
      {
        k8s_token = {
          sopsFile = ./secrets.enc.yaml;
        };
      }
    ];

    # advanced bcachefs support
    boot.supportedFilesystems = [ "bcachefs" ];
    boot.kernelModules = [ "bcachefs" ];
    # use latest kernel - required by bcachefs
    boot.kernelPackages = pkgs.linuxPackages_latest;

    
    # Late-mounting service
    systemd.services.mount-bcachefs = {
      description = "Mount bcachefs test filesystem";
      path = [
        pkgs.bcachefs-tools
        pkgs.util-linux
        pkgs.gawk
      ];

      # Start after basic system services are up
      after = [
        "network.target"
        "local-fs.target"
        "multi-user.target"
      ];

      # Don't consider boot failed if this service fails
      wantedBy = [ "multi-user.target" ];

      # Service configuration
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "+${pkgs.coreutils}/bin/mkdir -p ${cfg.mountpoint}";
      };

      # The actual mount script
      script = ''
        # Mount the filesystem if not already mounted
        if ! mountpoint -q ${cfg.mountpoint}; then
          UUID=$(bcachefs show-super ${cfg.bcachefsInitDevice} | grep Ext | awk '{print $3}')
          mount -t bcachefs UUID=$UUID ${cfg.mountpoint}
        fi
      '';

    };

    environment.systemPackages = with pkgs; [
      bcachefs-tools
      util-linux
      smartmontools
    ];

    programs.zsh.enable = true;
    services.openssh.enable = true;

    projectinitiative = {

      system = {
        # Enable common base modules
        console-info.ip-display = enabled;
      };

      networking = {
        tailscale = enabled;
      };
  
    };


    # Common network configuration
    networking.interfaces.${cfg.interface} = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = lib.removeSuffix "/24" cfg.ipAddress;
          prefixLength = 24;
        }
      ];
    };
    # networking.defaultGateway = cfg.gateway ? config.sensitiveNotSecret.default_gateway;
    networking.defaultGateway = "172.16.1.1";
    networking.nameservers = [ "172.16.1.1" "1.1.1.1" "9.9.9.9" ];
    networking.enableIPv6  = false;


  };
}
