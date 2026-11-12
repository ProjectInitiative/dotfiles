{ pkgs, ... }:
{
  home.username = "kylepzak";
  home.homeDirectory = "/home/kylepzak";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    atuin
    bat
    coreutils
    direnv
    eza
    fd
    git
    helix
    jq
    ripgrep
    zellij
    zoxide
  ];

  programs.home-manager.enable = true;
  programs.zsh.enable = true;
  programs.git = {
    enable = true;
    userName = "Kyle Pzak";
    userEmail = "6314611+ProjectInitiative@users.noreply.github.com";
  };
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  programs.atuin.enable = true;
  programs.helix.enable = true;

  home.sessionVariables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };
}
