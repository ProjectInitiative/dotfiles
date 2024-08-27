# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hosts/thinkpad/hardware-configuration.nix
      <home-manager/nixos>
    ];
  # enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # networking.hostName = "nixos"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  environment.sessionVariables = {
    GPG_TTY = "$(tty)";
  };

  environment.extraInit = ''
    export GPG_TTY=$(tty)
  '';

  # Enable networking  
  networking = {
    networkmanager.enable = true;    
  };

  # Disable wait online service
  systemd.services.NetworkManager-wait-online.enable = false;

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

  # hyprland
  programs.hyprland = {
    # Install the packages from nixpkgs
    enable = false;
    # Whether to enable XWayland
    xwayland.enable = true;
    # The hyprland package to use
    package = pkgs.hyprland;

    # Optional
    # Whether to enable hyprland-session.target on hyprland startup
    # systemd.enable = true;
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;


  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  # services.xserver.desktopManager.gnome.enable = true;

  services.xserver.desktopManager.gnome = {
    enable = true;
    extraGSettingsOverrides = ''
      [org.gnome.mutter]
      edge-tiling=true
      [org.gnome.desktop.wm.preferences]
      button-layout=':minimize,maximize,close'
    '';
  };

  # environment.gnome.excludePackages = (with pkgs; [
  #   gnome-photos
  #   gnome-tour
  #   gnome-music
  #   geary # email reader
  #   tali # poker game
  #   iagno # go game
  #   hitori # sudoku game
  #   atomix # puzzle game
  # ]) ++ (with pkgs.gnome; [
  #   cheese # webcam tool
  #   gnome-terminal
  #   gedit # text editor
  #   epiphany # web browser
  #   evince # document viewer
  #   gnome-characters
  #   totem # video player
  # ]);

 # Enable GNOME Shell extensions for all users
  environment.sessionVariables = {
    GNOME_SHELL_EXTENSIONS = with pkgs.gnomeExtensions; [
      # "${appindicator}/share/gnome-shell/extensions/appindicator@gnome-shell-extensions.gcampax.github.com"
      "${dash-to-dock}/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com"
      "${quake-mode}/share/gnome-shell/extensions/quake-mode@repsac-by.github.com"
      # Add paths for more extensions as needed
    ];
  };

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.  
  # sound.enable = true;  
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

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

 # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.kylepzak = {
    isNormalUser = true;
    description = "Kyle Petryszak";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
    ];
  };
      # terraform
      # parsec-bin
      # steam

# environment.variables = {
#   MOZILLA_HOME = "/home/kylepzak/.mozilla";
#   MOZ_LEGACY_PROFILES = "1";
# };

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
    trufflehog
    gitleaks
    gnupg
    pinentry
    pinentry-curses  # for terminal use
    pinentry-qt  # if you're using a graphical environment
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
    ripgrep
    ansible
    ansible-lint
    atuin
    gnome-tweaks
    gnomeExtensions.dash-to-dock
    gnomeExtensions.quake-mode
    gnomeExtensions.pop-shell
  ];



  
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    # syntaxHighlighting = true;
    interactiveShellInit = ''
      eval "$(${pkgs.atuin}/bin/atuin init zsh)"
    '';
  };
  # Set Zsh as the default shell for all users
  users.defaultUserShell = pkgs.zsh;

  security.sudo = {
    enable = true;
    extraConfig = ''
      # Set sudo timeout to 4 hours (14400 seconds)
      Defaults timestamp_timeout=14400
    '';
  };

  # enable tailscale
  services.tailscale.enable = true;


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
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-curses;
  };
  services.pcscd.enable = true;


  # home manager

  # Enable home-manager
  # home-manager.enable = true;
  home-manager.useGlobalPkgs = true;

  # Home Manager configuration
  home-manager.users.kylepzak = { pkgs, ... }: {

    # Home Manager needs a bit of information about you and the
    # paths it should manage.
    home.username = "kylepzak";
    home.homeDirectory = "/home/kylepzak";

    # This value determines the Home Manager release that your
    # configuration is compatible with. It's recommended to use
    # the same value as your NixOS system.stateVersion.
    home.stateVersion = "24.05";

    
    # specify user specific packages
    home.packages = with pkgs; [
      firefox
      chromium
      thunderbird
      freecad
      spotify
      bitwarden
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
    ];
    
    # existing dotfile configurations
    home.file = {
      ".config/zellij/config.kdl".source = ../dotfiles/zellij/zellij;
      ".config/helix/config.toml".source = ../dotfiles/helix/config.toml;
      ".alacritty.yml".source = ../dotfiles/.alacritty.yml;
      ".bashrc".source = ../dotfiles/.bashrc;
      ".zshrc".source = ../dotfiles/.zshrc;
    };

    # Ensure the target directories exist
    home.file.".config/zellij/.keep".text = "";
    home.file.".config/helix/.keep".text = "";

    # ... (any other home-manager configurations)
  };

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
  system.stateVersion = "24.05"; # Did you read the comment?

}

