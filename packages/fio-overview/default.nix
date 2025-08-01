# default.nix
{
  pkgs ? import <nixpkgs> { },
}:

let
  # Define the shell application (your fio-test.sh script) here.
  # This creates a self-contained executable script in the Nix store.
  fioTestScript = pkgs.writeShellApplication {
    name = "fio-overview"; # The name of the executable script within its own derivation
    runtimeInputs = [
      pkgs.bashInteractive # Provides bash itself
      pkgs.coreutils # Provides common utilities like echo, find, etc.
      pkgs.findutils # Provides the 'find' command for cleanup
      pkgs.fio # The Flexible I/O Tester executable
    ];
    # Read the content of your fio-test.sh script to be the body of this shell application
    text = builtins.readFile ./fio-test.sh;
  };
in

pkgs.stdenv.mkDerivation rec {
  pname = "fio-overview";
  version = "1.0";

  # The source is the current directory containing default.nix and fio-test.sh
  src = ./.;

  # propagatedBuildInputs are dependencies needed for the build of this derivation,
  # or for anything that depends on this derivation.
  # For the script itself, runtimeInputs in writeShellApplication are more direct.
  # Keeping them here ensures they are available in the build environment.
  propagatedBuildInputs = [
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.findutils
    pkgs.fio
  ];

  # No custom build phase is needed for a simple script

  # Install phase: This is where we copy the generated script to the output directory.
  installPhase = ''
    runHook preInstall # Standard hook for Nix derivations

    # Create the target binary directory within the output path
    install -d $out/bin

    # Copy the actual executable script from within the fioTestScript's output directory
    install -Dm755 ${fioTestScript}/bin/fio-overview $out/bin/fio-overview

    runHook postInstall # Standard hook for Nix derivations
  '';

  # Optional: Metadata about the package
  meta = with pkgs.lib; {
    description = "Performs general FIO performance tests on a filesystem.";
    longDescription = ''
      A script to perform a series of FIO (Flexible I/O Tester) benchmarks
      on a filesystem. It tests sequential reads/writes,
      random reads/writes (IOPS), and a mixed read/write workload.

      The script is designed to test general filesystem performance,
      taking into account bcachefs's tiering capabilities.

      WARNING: This script creates large temporary files on the specified
      filesystem. Ensure you have sufficient free space. While it attempts
      to clean up its own files, always exercise caution when running
      performance benchmarks on production systems.
    '';
    homepage = "https://example.com/your-repo"; # Optional: Replace with actual URL if you have one
    license = licenses.mit; # Example: Replace mit with your chosen license
    platforms = platforms.linux;
    # maintainers = [ maintainers.your_github_handle ]; # Optional: Add your handle
  };
}
