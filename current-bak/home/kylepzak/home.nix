{
  stateVersion,
  lib,
  config,
  pkgs,
  flakeRoot,
  ...
}:

let
  replaceSecrets =
    file: secretsMap:
    let
      placeholders = lib.mapAttrsToList (name: value: "{{${name}}}") secretsMap;
      secrets = lib.attrValues secretsMap;
      content = builtins.readFile file;
    in
    builtins.foldl' (
      str: placeholder: secret:
      builtins.replaceStrings [ placeholder ] [ secret ] str
    ) content placeholders secrets;

  envConfig = builtins.getEnv "HOME" + "/.env";
  loadedEnv = lib.mapAttrs (name: value: builtins.getEnv name) (
    builtins.fromJSON (builtins.readFile envConfig)
  );

  helixLanguagesConfig = replaceSecrets ./dotfiles/helix/languages.toml {
    ollama_address = loadedEnv.ollama_address;
  };
in
{
  # imports = [
  #   <sops-nix/modules/home-manager/sops.nix>
  # ];

  # sops = {
  #   defaultSopsFile = (flakeRoot + /secrets/home.enc.yaml);
  #   secrets.ollama_address = {};
  # };

  # Home Manager needs a bit of information about you and the paths it should manage.
  home.username = "kylepzak";
  home.homeDirectory = "/home/kylepzak";

  # This value determines the Home Manager release that your configuration is
  # compatible with. It's recommended to use the same value as your NixOS system.
  home.stateVersion = stateVersion;

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # User-specific packages
  home.packages = with pkgs; [
    # firefox
  ];

  # Git configuration
  programs.git = {
    enable = true;
    userName = "Kyle Petryszak";
    userEmail = "6314611+ProjectInitiative@users.noreply.github.com";
    extraConfig = {
      push = {
        autoSetupRemote = true;
      };
    };
  };

  # Zsh configuration (user-specific settings)
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = false;
      theme = "robbyrussell";
      plugins = [
        "git"
        "docker"
        "kubectl"
      ];
    };
  };

  # Copy dotfiles
  home.file = {
    # ".config/zellij/zellij".source = ./dotfiles/zellij/zellij;
    ".config/helix/config.toml".source = ./dotfiles/helix/config.toml;
    ".config/helix/themes".source = ./dotfiles/helix/themes;
    # ".config/helix/languages.toml".source = helixLanguagesConfig;
    ".alacritty.toml".source = ./dotfiles/.alacritty.toml;
    ".config/atuin/config.toml".source = ./dotfiles/atuin/config.toml;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}
