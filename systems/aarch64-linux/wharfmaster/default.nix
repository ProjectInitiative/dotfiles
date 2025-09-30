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

  imports = inputs.nixos-on-arm.bootModules.orangepi5ultra ++ [
    "${inputs.unstable}/pkgs/misc/uboot/default.nix"
  ];

  disabledModules = [ "pkgs/misc/uboot/default.nix" ];

  # nixpkgs.overlays = [
  #   (final: prev: {
  #     # take U-Boot family from unstable
  #     inherit (inputs.unstable.legacyPackages.${prev.system}) buildUBoot ubootTools;
  #   })
  # ];

  home-manager.backupFileExtension = "backup";



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
      monitoring.enable = true;
      attic = {
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
