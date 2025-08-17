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
      suites = {
        monitoring = enabled;
        attic = {
          enableClient = true;
        };
      };

      system = {
        nix-config.enable = true;
      };

      services = {

        k8s = {
          enable = true;
          tokenFile = sops.secrets.k8s_token.path;
          isFirstNode = cfg.isFirstK8sNode;
          serverAddr = cfg.k8sServerAddr;
          role = cfg.role;
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
