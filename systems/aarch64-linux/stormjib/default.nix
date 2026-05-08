# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).
#
# nix build .\#nixosConfigurations.stormjib.config.system.build.rockchipImages

{
  config,
  inputs,
  pkgs,
  lib,
  modulesPath,
  ...
}:
{
  imports = inputs.nixos-on-arm.bootModules.e52c;

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  boot.supportedFilesystems.zfs = lib.mkForce false;
  hardware.deviceTree.kernelPackage = lib.mkForce config.boot.kernelPackages.kernel;

  boot.extraModulePackages = [ config.boot.kernelPackages.r8125 ];
  boot.blacklistedKernelModules = [ "r8169" ];

  projectinitiative = {
    services = {
      monitoring = {
        enable = true;
        openFirewall = true;

        prometheus = {
          enable = true;
          retentionTime = "90d";

          scrapeConfigs = {
            nodes = {
              targets = [
                "172.16.1.51:9100"
                "172.16.1.52:9100"
                "172.16.1.53:9100"
                "lighthouse-east:9100"
                "lighthouse-west:9100"
              ];
            };
            smart-devices = {
              targets = [
                "172.16.1.51:9633"
                "172.16.1.52:9633"
                "172.16.1.53:9633"
                "lighthouse-east:9633"
                "lighthouse-west:9633"
              ];
            };
          };
        };

        grafana.enable = true;

        exporters = {
          node.enable = true;
          smartctl.enable = true;
        };
      };
    };
    hosts.masthead = {
      stormjib.enable = true;
      interfaces = {
        wan = "enP3p49s0";
        lan = "enP4p65s0";
        sync = "enP5p81s0";
      };
      wanSpoofMac = "02:00:00:00:00:01";
    };
    networking = {
      tailscale = {
        enable = true;
        ephemeral = false;
        extraArgs = [
          "--accept-dns=false"
          "--accept-routes"
        ];
      };
    };
    system = {
      console-info.ip-display.enable = true;
    };
  };

  console.enable = true;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Enable NetworkManager for easier network setup
  networking = {
    networkmanager = {
      enable = true;
    };
    useDHCP = lib.mkForce true;
  };
}
