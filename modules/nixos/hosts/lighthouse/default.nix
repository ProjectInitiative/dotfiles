{ config, lib, pkgs, namespace, ... }:

with lib;
with lib.${namespace};
let
  cfg = config.${namespace}.hosts.lighthouse;
  sops = config.sops;
in
{
  options.${namespace}.hosts.lighthouse = {
    enable = mkBoolOpt false "Whether to enable base Hetzner k8s node configuration.";
    role = mkOpt (types.enum [ "server" "agent" ]) "agent" "The role of the k8s node.";
    k8sServerAddr = mkOpt types.str "" "Address of the server node to connect to.";
    isFirstK8sNode = mkBoolOpt false "Whether node is the first in the cluster";
  };

  config = mkIf cfg.enable {
    # Define the sops secret for the k8s token
    sops.secrets.k8s_token = {
      sopsFile = ./secrets.enc.yaml; # Ensure this path is correct
    };

    # Basic system packages
    environment.systemPackages = with pkgs; [
      vim
      git
      wget
      curl
      htop
    ];

    # Networking -- Hetzner provides IP via DHCP
    networking.useNetworkd = true;
    networking.networkmanager.enable = false;

    # # Firewall rules for k3s
    # networking.firewall.allowedTCPPorts = [
    #   # Kube-API server
    #   6443
    # ] ++ (
    #   # Ports for agents
    #   if cfg.role == "agent" then [
    #     10250 # Kubelet
    #   ] else [ ]
    # );
    # networking.firewall.allowedUDPPorts = [
    #   8472 # Flannel VXLAN
    # ];

    # Kubernetes (k3s) configuration
    projectinitiative = {
      networking = {
        tailscale = {
            enable = true;
            ephemeral = false;
            extraArgs = [
              "--accept-dns=false"
              # "--accept-routes=true"
              # "--advertise-routes=10.0.0.0/24"
              # "--snat-subnet-routes=false"
              "--accept-dns=false"
              "--accept-routes=false"
              "--advertise-routes="
              "--snat-subnet-routes=true"
            ];
          };
        };
      services = {

        eternal-terminal = enabled;

        k8s = {
          enable = true;
          tokenFile = sops.secrets.k8s_token.path;
          isFirstNode = cfg.isFirstK8sNode;
          serverAddr = cfg.k8sServerAddr;
          role = cfg.role;
          networkType = "tailscale";
          extraArgs = [
              # TLS configuration
              "--tls-san=k8s.projectinitiative.io"

              # Security
              "--secrets-encryption"
              "--disable=traefik"
          ];
        };
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
    users.users.root.hashedPasswordFile = sops.secrets.root_password.path;
  };
}
