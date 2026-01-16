{
  inputs,
  config,
  lib,
  pkgs,
  namespace,
  ...
}:

with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.lightship;
  sops = config.sops;


  # This reads your local file and writes it to a new, independent
  # file in the Nix store. The `k3sEnvFile` variable will hold the
  # resulting store path (e.g., /nix/store/<hash>-k3s-lighthouse-env).
  # k3sEnvFile = pkgs.writeTextFile {
  #   name = "k3s-lightship-env";
  #   text = builtins.readFile ./k3s-lightship-env;
  # };

in
{
  options.${namespace}.hosts.lightship = {
    enable = mkBoolOpt false "Whether to enable base lightship k8s node configuration.";
    role = mkOpt (types.enum [
      "server"
      "agent"
    ]) "agent" "The role of the k8s node.";
    k8sServerAddr = mkOpt types.str "" "Address of the server node to connect to.";
    isFirstK8sNode = mkBoolOpt false "Whether node is the first in the cluster";
    k3sDataDir = mkOpt types.path "/var/lib/rancher/k3s" "Directory to use for k3s data.";
  };

  config = mkIf cfg.enable {

    # Define the sops secret for the k8s token
    sops.secrets = mkMerge [
      {
        k8s_token = {
          sopsFile = ./secrets.enc.yaml;
        };
      }
    ];

    #######################################################
    # CUSTOM FIRMWARE
    #######################################################
    
    boot.supportedFilesystems = {
      zfs = false;
    };

    boot.kernelParams = [
      "nvme_core.default_ps_max_latency_us=0"
      "pcie_aspm=off"
    ];

    # boot.kernelPatches = [{
    #   name = "rock-5a-led-overlay";
    #   patch = null;
    #   extraDts = ''
    #     /dts-v1/;
    #     /plugin/;

    #     &leds {
    #         green-led {
    #             compatible = "gpio-leds";
    #             gpios = <&gpio3 20 GPIO_ACTIVE_HIGH>; /* Corresponds to RK_PC4 */
    #             label = "green:power";
    #             linux,default-trigger = "default-on";
    #         };
    #     };
    #   '';
    # }];
    # 
    hardware.deviceTree.overlays = [
      # {
      #   name = "rock-5a-leds";
      #   dtsFile = ./rock-5a-leds.dts;
      # }
      {
        name = "rk3588-npu";
        dtsFile = "${inputs.self}/modules/nixos/hosts/lightship/rk3588s-rock-5a-npu.dts";
      }
    ];

    # not needed, latest kernel is merged
    # https://github.com/torvalds/linux/tree/v6.18/arch/arm64/boot/dts/rockchip
    # boot.kernelPatches = [
    #   {
    #     name = "rock-5a-green-led-fix";
    #     patch = ./rock-5a-led.patch;
    #   }
    # ];

    systemd.services.custom-leds = {
      description = "Custom LED Configuration";
      script = ''
        echo none > /sys/class/leds/blue\:status/trigger
        echo none > /sys/class/leds/green\:power/trigger
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      wantedBy = [ "multi-user.target" ];
    };

    # Systemd service to set thermal governor (replaces /config/config.txt)
    systemd.services.thermal-governor = {
      description = "Set Thermal Governor to power_allocator";
      script = ''
        echo power_allocator > /sys/devices/virtual/thermal/thermal_zone0/policy
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      wantedBy = [ "multi-user.target" ];
    };


  systemd.services.pwm-fan-control = {
    description = "Set PWM Fan to Reasonable Speed";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-devices-platform-pwm\\x2dfan.device" ];
    path = with pkgs; [ coreutils findutils gnugrep ];
    script = ''
      sleep 3  # Wait for hwmon to be ready
    
      # Find the actual hwmon device (not the parent directory)
      HWMON_PATH=$(find /sys/devices/platform/pwm-fan/hwmon -name "hwmon*" -type d | grep -v "hwmon$" | head -1)
    
      if [ -n "$HWMON_PATH" ]; then
        echo "Setting PWM fan to manual mode and 30% speed"
        echo 1 > "$HWMON_PATH/pwm1_enable"
        echo 77 > "$HWMON_PATH/pwm1"  # 30% speed
        echo "PWM fan set to 30% speed at $HWMON_PATH"
      else
        echo "Could not find hwmon device"
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
    
  # Load the watchdog kernel module
  # boot.kernelModules = [ "rockchip_wdt" ];

  # # Configure and enable the watchdog service
  # hardware.watchdog = {
  #   enable = true;
  #   device = "/dev/watchdog";
  #   interval = 10;
  #   interfaces = [ "tailscale0" ];
  #   # The original Ansible script used 'ansible_host' (the machine's own IP).
  #   # Pinging the machine itself can be a basic check that the network stack is up.
  #   # I am using the IP from k8sServerAddr as a placeholder.
  #   ping = [ "100.94.107.39" ];
  # };
    #######################################################

    

    programs.zsh.enable = true;

    # Enable and configure SSH, restricting access to public keys only
    services.openssh = {
      enable = true;
      # Disable password-based authentication for security.
      settings = {
        PasswordAuthentication = true;
        KbdInteractiveAuthentication = true; # Disables keyboard-interactive auth, often a fallback for passwords.
        PermitRootLogin = "prohibit-password"; # Allows root login with a key, but not a password.
      };
    };

    networking = {
      networkmanager = {
        enable = true;
      };
      useDHCP = lib.mkForce true;
    };

    # Kubernetes (k3s) configuration
    projectinitiative = {

      networking = {
        tailscale = {
          enable = true;
          ephemeral = false;
          extraArgs = [
            "--accept-routes=true"
            # "--advertise-routes=10.0.0.0/24"
            # "--snat-subnet-routes=false"
            "--accept-dns=false"
            # "--accept-routes=false"
            "--advertise-routes="
            "--snat-subnet-routes=true"
          ];
        };
      };
      suites = {
        monitoring = enabled;
        loft = {
          enableClient = true;
        };
      };

      system = {
        nix-config.enable = true;
      };

      services = {

        monitoring.alloy.enable = mkForce false;

        k8s = {
          enable = true;
          tokenFile = sops.secrets.k8s_token.path;
          isFirstNode = cfg.isFirstK8sNode;
          serverAddr = cfg.k8sServerAddr;
          role = cfg.role;
          dataDir = cfg.k3sDataDir;
          networkType = "tailscale";
          # environmentFile = k3sEnvFile;
          extraArgs = [
            # TLS configuration
            "--tls-san=k8s.projectinitiative.io"

            # Security
            "--secrets-encryption"
            "--disable=traefik"
            "--disable local-storage"
          ];
        };
      };
    };

  };
}
