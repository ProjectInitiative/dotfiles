{ pkgs ? import <nixpkgs> { } }:

pkgs.stdenv.mkDerivation rec { # 'rec' allows referring to 'name' and 'version' within the derivation
  pname = "bcachefs-snap"; # Package name
  version = "0.1.0";     # Version of your utility

  # Source directory: assumes default.nix and bcachefs_snap.py are in the same directory.
  src = ./.;

  # Runtime dependencies needed by the script.
  # These will be available in the environment where the script runs.
  propagatedBuildInputs = [
    pkgs.python3         # The Python 3 interpreter
    pkgs.bcachefs-tools  # Provides the 'bcachefs' command-line utility
    # If you add Python libraries not in the standard library (e.g., PyYAML),
    # you would add them here like: pkgs.python3Packages.pyyaml
  ];

  # Installation phase:
  # This describes how to "install" the script into the Nix store.
  installPhase = ''
    runHook preInstall # Standard Nix hook

    # Create the target directory in the output path ($out)
    mkdir -p $out/bin

    # Copy the script to $out/bin and make it executable.
    # 'bcachefs_snap.py' refers to the file from the 'src' directory.
    install -Dm755 bcachefs-snap.py $out/bin/${pname}
    # The script will be available as 'bcachefs-snap' in the PATH after installation.

    # Example: If you wanted to install a default/example config file:
    # mkdir -p $out/etc/bcachefs-snap
    # install -Dm644 bcachefs-snap.conf $out/etc/bcachefs-snap/bcachefs-snap.conf.example
    # Users would then copy this to /etc/bcachefs-snap.conf or similar.

    runHook postInstall # Standard Nix hook
  '';

  # Meta information about the package (optional but good practice)
  meta = with pkgs.lib; {
    description = "A utility for creating and managing bcachefs snapshots with retention policies";
    longDescription = ''
      bcachefs-snap is a Python-based command-line tool to automate the creation
      and pruning of snapshots on bcachefs filesystems. It supports configurable
      retention policies (hourly, daily, weekly, monthly, yearly) and can be
      driven by a configuration file or command-line arguments.
    '';
    homepage = "https://github.com/yourusername/bcachefs-snap"; # Replace with your actual repo URL if you have one
    license = licenses.mit; # Choose an appropriate license (e.g., licenses.gpl3Plus)
    maintainers = [ maintainers.yourGithubUsername ]; # Replace with your GitHub username
    platforms = platforms.linux; # bcachefs is Linux-specific
  };
}

