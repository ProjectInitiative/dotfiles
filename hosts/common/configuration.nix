# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

let
  commonPackages = import ../../packages/common.nix { inherit pkgs; };
  tempOverlay = self: super: {
    lsp-ai = self.callPackage ../../packages/custom/lsp-ai/package.nix {};
  };
in
{
  nixpkgs.overlays = [ tempOverlay ];
  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Networking
  networking.networkmanager.enable = true;
  systemd.services.NetworkManager-wait-online.enable = false;

  # Enable SSH
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };


  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.kylepzak = {
    isNormalUser = true;
    description = "Kyle Petryszak";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile
  environment.systemPackages = commonPackages;

  # Zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    interactiveShellInit = ''
      eval "$(${pkgs.atuin}/bin/atuin init zsh)"
      eval "$(zoxide init zsh)"
      export PATH="''${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
    '';
    shellAliases = {
      refresh = "source ~/.zshrc";
      make = "make -j $(nproc)";
      k = "kubectl";
      kx = "kubectl ctx";
      kn = "kubectl ns";
      tailscale-up = "sudo tailscale up --login-server https://ts.projectinitiative.io --accept-routes";
      ap = "ansible-playbook";
      grep = "rg";
      ls = "exa";
      ll = "exa -al";
      cat = "bat";
      cd = "z";
    };
  };
  users.defaultUserShell = pkgs.zsh;

  # Sudo configuration
  security.sudo = {
    enable = true;
    extraConfig = ''
      # Set sudo timeout to 4 hours (14400 seconds)
      Defaults timestamp_timeout=14400
    '';
  };

  # Enable tailscale
  services.tailscale.enable = true;

  # Enable containers
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = false;
      defaultNetwork.settings.dns_enabled = true;
    };
    docker = {
      enable = true;
    };
  };
  users.extraGroups.docker.members = [ "kylepzak" ];

  # Enable programs
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
  };
  services.pcscd.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
