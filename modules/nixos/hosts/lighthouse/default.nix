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
  cfg = config.${namespace}.hosts.lighthouse;
  sops = config.sops;

  # default attic suite settings:
  defaultAtticSettings = config.${namespace}.suites.attic.settings;

  # This reads your local file and writes it to a new, independent
  # file in the Nix store. The `k3sEnvFile` variable will hold the
  # resulting store path (e.g., /nix/store/<hash>-k3s-lighthouse-env).
  k3sEnvFile = pkgs.writeTextFile {
    name = "k3s-lighthouse-env";
    text = builtins.readFile ./k3s-lighthouse-env;
  };

in
{
  options.${namespace}.hosts.lighthouse = {
    enable = mkBoolOpt false "Whether to enable base Hetzner k8s node configuration.";
    role = mkOpt (types.enum [
      "server"
      "agent"
    ]) "agent" "The role of the k8s node.";
    k8sServerAddr = mkOpt types.str "" "Address of the server node to connect to.";
    isFirstK8sNode = mkBoolOpt false "Whether node is the first in the cluster";
  };

  config = mkIf cfg.enable {
    # Define the sops secret for the k8s token

    programs = {
      atop = {
        enable = true;
      };
    };

    # Basic system packages
    environment.systemPackages = with pkgs; [
      vim
      helix
      git
      wget
      curl
      htop
      btop
    ];

    #####################################################
    # PUBLIC CLOUD EXPLICITLY DEFINE AND OVERRIDE SECURITY CONTROLS
    #####################################################
    #
    # DISABLE ALL DEFAULTS FOR USER
    home-manager.users = mkForce { };
    # CREATE BAREBONES USER
    users.users.kylepzak = mkForce {
      isNormalUser = true;

      name = "kylepzak";

      home = "/home/kylepzak";
      group = "users";

      extraGroups = [ "wheel" ];

      shell = pkgs.zsh;

      openssh.authorizedKeys.keys = mkForce [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKxw1azMwGx2sEs2HipWWjRjQ4EIqL5Hx8HHGtUk602c"
      ];

      hashedPasswordFile = sops.secrets.user_password.path;
    };

    programs.zsh.enable = true;

    # FAIL2BAN
    services.fail2ban = {
      enable = true;

      # Global default: Ban after 5 failures
      maxretry = 5;

      # Global default: Ban for 24 hours (your preference)
      bantime = "24h";

      # Allowlist trusted IPs.
      # ignoreIP = [
      #   "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16"
      #   "8.8.8.8" # Example of a trusted static IP
      # ];

      # Exponential backoff for repeat offenders
      bantime-increment = {
        enable = true;
        formula = "ban.Time * math.exp(float(ban.Count+1)*banFactor)/math.exp(1*banFactor)";
        maxtime = "168h"; # Max ban of 1 week
        overalljails = true;
        # 'multipliers' line removed to fix conflict with 'formula'
      };

      jails = {
        # CRITICAL: Protects SSH from brute-force scans and log spam
        sshd.settings = {
          enable = true;
          # This jail will use your global 24h bantime and 5 maxretry
        };

      };
    };

    # ROOT PASSWORD UNSETABLE
    users.users.root.hashedPassword = mkForce "!";

    # ALL SUDO NEEDS AUTH
    security.sudo.wheelNeedsPassword = mkForce true;
    security.sudo-rs.wheelNeedsPassword = mkForce true;

    # ONLY INCLUDE REQUIRED SECRETS
    enableCommonEncryption = mkForce false;
    sops = mkForce {
      defaultSopsFile = ./secrets.enc.yaml;
      secrets = {
        k8s_token = { };
        user_password = {
          neededForUsers = true;
        };
        tailscale_auth_key = { };
      };
    };

    # Enable and configure SSH, restricting access to public keys only
    services.openssh = {
      enable = true;
      # Disable password-based authentication for security.
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false; # Disables keyboard-interactive auth, often a fallback for passwords.
        PermitRootLogin = "prohibit-password"; # Allows root login with a key, but not a password.
      };
    };
    #####################################################

    # Networking -- cloud provides IP via DHCP
    #
    #####################################################
    # PUBLIC CLOUD EXPLICITLY DEFINE AND OVERRIDE ANY PORTS
    #####################################################
    networking = mkForce {
      useNetworkd = true;
      networkmanager.enable = false;

      firewall = {
        enable = true;
        allowPing = false;
        allowedTCPPorts = [
          # only SSH through tailscale
          # 22
          # specific ports
          80
          443
        ];
        allowedTCPPortRanges = [ ];
        allowedUDPPorts = [
          # DNS
          53
          # Tailscale
          41641
        ];
        allowedUDPPortRanges = [ ];
      };

    };

    #####################################################

    # Kubernetes (k3s) configuration
    projectinitiative = {

      ## DISABLE USER GEN ##
      user.enable = mkForce false;

      networking = {
        tailscale = {
          enable = true;
          ephemeral = false;
          extraArgs = [
            # "--accept-routes=true"
            # "--advertise-routes=10.0.0.0/24"
            # "--snat-subnet-routes=false"
            "--accept-dns=false"
            "--accept-routes=true"
            "--advertise-routes="
            "--snat-subnet-routes=true"
          ];
        };
      };
      suites = {
        monitoring = enabled;
        # Only add the trusted key, don't add access to the binary cache
        loft = {
          enable = true;
          trustKeyOnly = true;
        };
      };

      system = {
        nix-config.enable = true;
      };

      services = {

        attic.client = {
          enable = false;
          cacheName = defaultAtticSettings.cacheName;
          serverUrl = defaultAtticSettings.serverUrl;
          publicKey = defaultAtticSettings.publicKey;
          manageNixConfig = true;
          autoLogin = false;
          watchStore.enable = false;
        };

        k8s = {
          enable = true;
          tokenFile = sops.secrets.k8s_token.path;
          isFirstNode = cfg.isFirstK8sNode;
          serverAddr = cfg.k8sServerAddr;
          role = cfg.role;
          networkType = "tailscale";
          environmentFile = k3sEnvFile;
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
