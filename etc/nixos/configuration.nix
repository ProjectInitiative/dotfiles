# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # Include bootloader info
      ./bootloader.nix
    ];


  # networking.hostName = "nixos"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Enable networking  
  networking.networkmanager.enable = true;    
  # # Set NIC info  
  # networking = {    
  # `# Disable DHCP    
  # useDHCP = false;    
  # defaultGateway = "172.16.1.1";    
  # interfaces = {
  #     # Configure the default interface
  #     "enp0s18" ={
  #       ipv4.addresses = [
  #         { address = "172.16.1.180"; prefixLength = 24; }
  #       ];
  #     };
  #   };
  # };

 # Enable SSH
 services.openssh = {
   enable = true;
   # require public key authentication
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

  # Enable the X11 windowing system.
  services.xserver.enable = true;


  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.  
  sound.enable = true;  
  hardware.pulseaudio.enable = false;  
  security.rtkit.enable = true;  
  services.pipewire = {   
   enable = true;    
    alsa.enable = true;    
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };
  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

 # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kylepzak = {
    isNormalUser = true;
    description = "Kyle Petryszak";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      firefox
      chromium
      thunderbird
      freecad
      tor
      tor-browser
      telegram-desktop
      signal-desktop
      solaar
      vlc
      backintime
      gimp
      wireshark
      kubectl
      krew
      kubernetes-helm
      kustomize
      vagrant
      packer
      python3
      rustup
      go
      awscli2
    ];
  };
      # terraform
      # parsec-bin
      # steam

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  # List packages installed in system profile. To search, run:
  # $ nix search wget

 # install fonts
  fonts.packages = with pkgs; [
    fira-code
    fira-code-symbols
  ];


  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    stow
    git
    gitui
    gnupg
    pinentry-curses
    helix
    alacritty
    zellij
    tailscale
    podman-compose
    docker-compose
    virtualbox
    quickemu
    quickgui
    appimage-run
    eza
    bat
    mcfly
    ripgrep
    ansible
    ansible-lint
  ];

  # https://discourse.nixos.org/t/cant-get-gnupg-to-work-no-pinentry/15373/21
  # GnuPG
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryFlavor = "curses";
  };
  services.dbus.packages = [ pkgs.gcr ];
  services.pcscd.enable = true;

  # enable containers
  virtualisation = {
    podman = {
      enable = true;

      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = false;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };
    docker = {
      enable = true;
    };
  };
  users.extraGroups.docker.members = [ "kylepzak" ];
  
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?

}

