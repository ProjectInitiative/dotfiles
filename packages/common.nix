# packages/common.nix
{ pkgs }:

with pkgs; [
  # Common packages for both NixOS and non-NixOS environments
  alacritty
  ansible
  ansible-Lint
  atin
  bat
  backintime
  eza
  git
  git-Filter-Repo
  gitleaks
  gnupg
  go
  helix
  htop
  kubectl
  kubernetes-Helm
  kustomize
  krew
  nix-Prefetch-Git
  nix-Prefetch-Github
  packer
  pinentry
  pinentry-Curses
  pinentry-Qt
  python3
  python3Packages.Pip
  ripgrep
  rustup
  stow
  trufflehog
  usbutils
  zellij
  zoxide
]
