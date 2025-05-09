# shell.nix
# This file defines a development environment for bcachefs-snap.
# To use it, run 'nix-shell' in the directory containing this file.

{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  # Name for the shell environment (optional, but good for prompts)
  name = "bcachefs-snap-dev";

  # Packages to make available in the development shell.
  # These are the same runtime dependencies as in the default.nix package.
  buildInputs = [
    pkgs.python3 # Python 3 interpreter
    pkgs.bcachefs-tools # Provides the 'bcachefs' command-line utility

    # Add any other tools you might need for development, for example:
    # pkgs.python3Packages.pylint # For linting Python code
    # pkgs.git # If you manage your project with Git
  ];

  # You can set environment variables for the shell here if needed.
  # shellHook = ''
  #   echo "Entered bcachefs-snap development environment."
  #   # Example: Set PYTHONPATH if your project has local modules
  #   # export PYTHONPATH=$(pwd):$PYTHONPATH
  # '';
}
