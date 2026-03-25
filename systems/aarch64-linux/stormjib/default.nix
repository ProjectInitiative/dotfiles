# the masthead routers will be named accordingly:
# Topsail (Primary) & StormJib (Backup)
#     Topsail: Agile sail for fair-weather speed (primary performance).
#     StormJib: Rugged sail for heavy weather (backup resilience).
#
# nom build .\#nixosConfigurations.stormjib.config.system.build.sdImage

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

  # Platform configuration for hybrid cross-compilation
  # This tells Nix to evaluate as aarch64-linux (for cache hits)
  # while the new image builder in nixos-on-arm uses hostPkgs (pkgs.buildPackages)
  # for native x86_64 image assembly.
  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.config.allowUnsupportedSystem = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Disable ZFS as it is often broken on latest kernels/ARM
  boot.supportedFilesystems.zfs = lib.mkForce false;

  boot.initrd.availableKernelModules = lib.mkForce [ ];

  # Rockchip board configuration
  rockchip = {
    # Configure which image variants to build
    image.buildVariants = {
      full = true; # Build full eMMC image with U-Boot (nixos-e52c-full.img)
      sdcard = true; # Build SD card image without U-Boot (os-only.img)
      ubootOnly = true; # Build U-Boot only image
    };
  };

  projectinitiative = {
    services = {
      monitoring = {
        enable = true;
        openFirewall = true;

        # Enable the Prometheus server on this node
        prometheus = {
          enable = true;
          retentionTime = "90d"; # Keep data for 90 days

          # Define jobs to scrape other nodes
          scrapeConfigs = {
            # A job named 'nodes' to scrape all your other servers
            nodes = {
              targets = [
                "172.16.1.51:9100"
                "172.16.1.52:9100"
                "172.16.1.53:9100"
                "lighthouse-east:9100"
                "lighthouse-west:9100"
              ];
            };
            # A job for scraping smartctl data if it's on a different port/host
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

        # Enable Grafana on this node
        grafana = {
          enable = true;
        };

        # Also enable exporters on this monitoring server itself.
        # The server will automatically pick these up under the 'self' job.
        exporters = {
          node.enable = true;
          smartctl.enable = true;
        };
      };
    };
    hosts.masthead.stormjib.enable = true;
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

  # SSH access
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
