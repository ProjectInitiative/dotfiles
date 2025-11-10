{
  config,
  pkgs,
  inputs,
  namespace,
  modulesPath,
  lib,
  ...
}:
{

  imports = inputs.nixos-on-arm.bootModules.orangepi5ultra;

  home-manager.backupFileExtension = "backup";

  environment.systemPackages = with pkgs; [
    pkgs.${namespace}.rknpu2
  ];

  programs.zsh.enable = true;

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

  services.comin =
    let
      livelinessCheck = pkgs.writeShellApplication {
        name = "comin-liveliness-check";
        runtimeInputs = [ pkgs.iputils pkgs.systemd ];
        text = ''
          echo "--- Starting Health Checks ---"

          echo "Pinging gateway 192.168.21.1..."
          ping -c 5 192.168.21.1

          echo "Checking docker service status..."
          systemctl is-active --quiet docker

          echo "--- Health Checks Complete ---"
        '';
      };
    in
    {
      enable = true;
      remotes = [{
        name = "origin";
        url = "https://github.com/projectinitiative/dotfiles.git";
        branches.main.name = "main";
      }];
      livelinessCheckCommand = "${livelinessCheck}/bin/comin-liveliness-check";
    };

  networking = {
    networkmanager = {
      enable = true;
    };
    useDHCP = lib.mkForce true;
    
    # VLAN configuration for vlan21
    interfaces.enP3p49s0.useDHCP = true;
    vlans."vlan21" = {
      id = 21;
      interface = "enP3p49s0";
    };
    interfaces.vlan21.useDHCP = true;
  };

  # setup funnel for home-assistant
  systemd.services.tailscale-funnel = {
    description = "Tailscale Funnel";
    after = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.tailscale}/bin/tailscale funnel --bg 8123";
      User = "root"; # Funnel needs root to bind to privileged ports
    };
  };

  projectinitiative = {

    networking = {
      tailscale = {
        enable = true;
        ephemeral = false;
        extraArgs = [
          "--accept-routes=true"
          # "--advertise-routes=10.0.0.0/24"
          # "--snat-subnet-routes=false"
          "--accept-dns=true"
          # "--accept-routes=false"
          "--advertise-routes="
          "--snat-subnet-routes=true"
        ];
      };
    };
    suites = {
      development = {
        enable = true;
      };
      monitoring.enable = true;
      loft = {
        enableClient = true;
      };
    };

    system = {
      nix-config.enable = true;
    };

    services = {

    };

  };


  system.stateVersion = lib.mkForce "25.05";

}
