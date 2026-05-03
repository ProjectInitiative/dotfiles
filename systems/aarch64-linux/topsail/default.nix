# Topsail (Primary): Agile sail for fair-weather speed (primary performance).
#
# nix build .\#nixosConfigurations.topsail.config.system.build.sdImage

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

  boot.initrd.availableKernelModules = [
    "dw_mmc_rockchip"
    "usbnet"
    "cdc_ether"
    "rndis_host"
  ];

  rockchip = {
    enable = true;
    uboot.package = pkgs.uboot-rk3582-generic;
    deviceTree = "rockchip/rk3582-radxa-e52c.dtb";
    console = {
      earlycon = "uart8250,mmio32,0xfeb50000";
      console = "ttyS4,1500000";
    };
    image.buildVariants = {
      full = true;
      sdcard = true;
      ubootOnly = true;
    };
  };

  projectinitiative = {
    services.monitoring = {
      enable = true;
      openFirewall = true;
      prometheus = {
        enable = true;
        retentionTime = "90d";
        scrapeConfigs.nodes = {
          targets = [
            "172.16.1.51:9100"
            "172.16.1.52:9100"
            "172.16.1.53:9100"
            "lighthouse-east:9100"
            "lighthouse-west:9100"
          ];
        };
        scrapeConfigs.smart-devices = {
          targets = [
            "172.16.1.51:9633"
            "172.16.1.52:9633"
            "172.16.1.53:9633"
            "lighthouse-east:9633"
            "lighthouse-west:9633"
          ];
        };
      };
      grafana.enable = true;
      exporters = {
        node.enable = true;
        smartctl.enable = true;
      };
    };
    hosts.masthead = {
      topsail.enable = true;
      interfaces = {
        wan = "enP3p49s0";
        lan = "enP4p65s0";
        sync = "enP5p81s0";
      };
      wanSpoofMac = "02:00:00:00:00:01";
    };
    networking.tailscale = {
      enable = true;
      ephemeral = false;
      extraArgs = [ "--accept-dns=false" "--accept-routes" ];
    };
    system.console-info.ip-display.enable = true;
  };

  console.enable = true;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  networking = {
    networkmanager.enable = true;
    useDHCP = lib.mkForce true;
  };
}
