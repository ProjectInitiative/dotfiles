# packages/common.nix
{ pkgs }:

with pkgs; [
  # Common packages for both NixOS and non-NixOS environments
  stow
  git
  kubectl
  krew
  kubernetes-helm
  kustomize
  git-filter-repo
  trufflehog
  gitleaks
  gnupg
  pinentry
  pinentry-curses
  pinentry-qt
  helix
  alacritty
  zellij
  eza
  bat
  zoxide
  ripgrep
  ansible
  ansible-lint
  atuin
  packer
  python3
  python3Packages.pip
  usbutils
  rustup
  go
]
