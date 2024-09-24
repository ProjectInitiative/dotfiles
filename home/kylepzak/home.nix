{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should manage.
  home.username = "kylepzak";
  home.homeDirectory = "/home/kylepzak";

  # This value determines the Home Manager release that your configuration is
  # compatible with. It's recommended to use the same value as your NixOS system.
  home.stateVersion = "24.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # User-specific packages
  home.packages = with pkgs; [
    bambu-studio
    bitwarden
    chromium
    element-desktop
    gimp
    firefox
    # freecad
    spotify
    signal-desktop
    telegram-desktop
    thunderbird
    tor-browser
    vagrant
    vlc
    wireshark
  ];

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Kyle Petryszak";
    userEmail = "6314611+ProjectInitiative@users.noreply.github.com";
  };

  # Zsh configuration (user-specific settings)
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = false;
      theme = "robbyrussell";
      plugins = [ "git" "docker" "kubectl" ];
    };
  };


  # Copy dotfiles
  home.file = {
    # ".config/zellij/zellij".source = ./dotfiles/zellij/zellij;
    ".config/helix/config.toml".source = ./dotfiles/helix/config.toml;
    ".config/helix/themes".source = ./dotfiles/helix/themes;
    ".alacritty.toml".source = ./dotfiles/.alacritty.toml;
    ".config/atuin/config.toml".source = ./dotfiles/atuin/config.toml;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}
