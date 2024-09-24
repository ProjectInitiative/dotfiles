# packages/common.nix
{ pkgs }:

with pkgs; [
  # Common packages for both NixOS and non-NixOS environments
  lsp-ai
  alacritty
  ansible
  ansible-lint
  atuin
  bat
  backintime
  borgbackup
  eza
  git
  git-filter-repo
  gitleaks
  gnupg
  go
  helix
  htop
  juicefs
  k9s
  kubectl
  kubernetes-helm
  kustomize
  krew
  ncdu
  nix-prefetch-git
  nix-prefetch-github
  packer
  pinentry
  pinentry-curses
  pinentry-qt
  python3
  python3Packages.pip
  python3Packages.python-lsp-server
  ripgrep
  rustup
  stow
  tree
  trufflehog
  usbutils
  zellij
  zoxide
]
