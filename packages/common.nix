# packages/common.nix
{ pkgs }:

with pkgs; [
  # Common packages for both NixOS and non-NixOS environments
  alacritty
  ansible
  ansible-lint
  atin
  bat
  backintime
  eza
  git
  git-filter-repo
  gitleaks
  gnupg
  go
  helix
  htop
  kubectl
  kubernetes-helm
  kustomize
  krew
  nix-prefetch-git
  nix-prefetch-github
  packer
  pinentry
  pinentry-curses
  pinentry-qt
  python3
  python3packages.pip
  ripgrep
  rustup
  stow
  trufflehog
  usbutils
  zellij
  zoxide
]
