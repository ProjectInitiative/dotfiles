# my-bcachefs-updater/default.nix
{
  # If imported directly, pkgs will be taken from <nixpkgs>.
  # If used in an overlay or your NixOS configuration, pkgs will be passed.
  pkgs ? import <nixpkgs> { },
}:

pkgs.stdenv.mkDerivation rec {
  pname = "bcachefs-update-refs";
  version = "1.0.0"; # You can change this version as you update the script

  # Source: Assumes default.nix and the script are in the same directory.
  # The script should be named 'update-bcachefs.sh' in this directory.
  src = ./.;

  # Runtime dependencies for the script. These will be available in $PATH
  # when the packaged script is executed.
  propagatedBuildInputs = [
    pkgs.bashInteractive # Provides bash
    pkgs.nix-prefetch-scripts # Provides nix-prefetch-github
    pkgs.jq # For parsing JSON output
    pkgs.gnused # Provides sed for in-file replacements
    pkgs.gnugrep # Provides grep
    pkgs.coreutils # For basic utilities like echo, cat, etc.
  ];

  # This script doesn't need a build phase (no compilation).
  dontBuild = true;

  # Install phase: Copy the script to $out/bin and make it executable.
  installPhase = ''
    runHook preInstall

    # Create the bin directory in the output path
    install -d $out/bin

    # Copy the script from the source directory to $out/bin,
    # name the executable 'bcachefs-update-refs', and make it executable.
    install -Dm755 $src/bcachefs-update-refs.sh $out/bin/bcachefs-update-refs

    runHook postInstall
  '';

  # Meta information about the package
  meta = with pkgs.lib; {
    description = "Updates bcachefs kernel and tools rev/hash in specified Nix files";
    longDescription = ''
      A script to automatically fetch the latest 'master' branch revisions and
      SRI hashes for koverstreet/bcachefs (kernel) and koverstreet/bcachefs-tools
      repositories using 'nix-prefetch-github'.

      It then uses 'sed' to update the 'rev' and 'hash' values directly within
      your specified NixOS module file for the bcachefs kernel and your overlay
      file for bcachefs-tools.

      IMPORTANT USAGE NOTE:
      This script expects to be run from the root of your NixOS configuration
      (e.g., your 'dotfiles' directory) where the relative paths
      'modules/nixos/system/bcachefs-kernel/default.nix' and
      'overlays/bcachefs-tools/default.nix' (as defined inside the script)
      are valid.
    '';
    homepage = ""; # Optional: Link to your dotfiles repo or where you keep the script
    license = licenses.mit; # Or your preferred license (e.g., licenses.gpl3Only)
    platforms = platforms.linux; # Primarily for NixOS/Linux environments
    # maintainers = [ maintainers.yourGithubHandle ]; # Optional: Add your GitHub handle
  };
}
