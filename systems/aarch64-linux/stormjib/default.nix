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

  boot.supportedFilesystems.zfs = lib.mkForce false;
  hardware.deviceTree.kernelPackage = lib.mkForce config.boot.kernelPackages.kernel;

  # Use out-of-tree r8125 driver — in-tree r8169 has 2.5G link flapping issue.
  # r8125 v9.016.01 from Debian, built against the patched kernel.
  boot.blacklistedKernelModules = [ "r8169" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.r8125 ];
  boot.kernelModules = [ "r8125" ];
  hardware.firmware = [ pkgs.linux-firmware ];

  rockchip.image.bootPartitionSize = "1G";

  boot.kernelParams = [
    "pcie_aspm=off"
  ];

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", NAME=="enP*", RUN+="${pkgs.ethtool}/bin/ethtool --set-eee $name eee off"
  '';

  # Keep as reference — may not be needed if firmware resolves the issue
  # systemd.services.fix-r8169-link = {
  #   ...
  # };

  # Try without PCIe overlay - default link training may work better
  hardware.deviceTree.enable = true;
  hardware.deviceTree.overlays = [
  ];

  # Limit boot entries to prevent ESP overflow (253M partition)
  boot.loader = {
    systemd-boot.enable = true;
    systemd-boot.configurationLimit = 4;
    efi.canTouchEfiVariables = true;
  };

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
      stormjib.enable = false;
      interfaces = {
        wan = "enP3p49s0";
        lan = "enP4p65s0";
        sync = "enP5p81s0";
      };
      # Use native MAC to rule out spoofing-related PHY issues
      wanSpoofMac = "00:48:54:20:12:0e";
    };
    networking = {
      tailscale = {
        enable = false;
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

  environment.systemPackages = with pkgs; [
    ethtool
    pciutils
    iperf3
  ];

  # Enable static networking for testing while masthead is disabled
  networking = {
    networkmanager.enable = false;
    useDHCP = false;
    interfaces = {
      enP4p65s0 = {
        useDHCP = false;
        ipv4.addresses = [{
          address = "172.16.1.3";
          prefixLength = 24;
        }];
      };
      # Disable WAN for diagnostic to rule out loops/conflicts
      enP3p49s0 = {
        useDHCP = false;
      };
    };
    defaultGateway = "172.16.1.1";
    nameservers = [ "172.16.1.1" "1.1.1.1" ];
  };
}
