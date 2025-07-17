# shell.nix
# This file defines a development/runtime environment for the bcachefs updater script.
# To use it, run 'nix-shell' in the directory containing this file.

{
  # If imported directly, pkgs will be taken from <nixpkgs>.
  # If used in an overlay or your NixOS configuration, pkgs will be passed.
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  # Name for the shell environment (optional, useful for shell prompts)
  name = "bcachefs-updater-env";

  # Packages to make available in the development/runtime shell.
  # These are the dependencies needed to run the update-bcachefs.sh script.
  buildInputs = [
    pkgs.bashInteractive # Provides bash
    pkgs.nix-prefetch-scripts # Provides nix-prefetch-github
    pkgs.jq # For parsing JSON output from nix-prefetch-github
    pkgs.gnused # Provides sed for in-file replacements
    pkgs.gnugrep # Provides grep (used in the script's checks)
    pkgs.coreutils # For basic utilities like echo, cat, etc.

    # Optional: Add other tools you might use for development or debugging
    # pkgs.git                    # If you manage the script with Git
    # pkgs.vim                    # Or your preferred editor
  ];

  # Optional: Environment variables or commands to run when the shell starts.
  shellHook = ''
    echo "Entered bcachefs updater environment."
    echo "The script 'bcachefs-update-ref.sh' can be run from your NixOS configuration root."
    echo "Ensure you are in the correct directory (e.g., your dotfiles root) before running:"
    echo "  ./bcachefs-update-ref.sh"
    echo ""
    echo "Required tools (nix-prefetch-github, jq, sed, grep) are now in your PATH."
  '';
}
