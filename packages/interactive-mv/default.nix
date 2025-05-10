# default.nix
{
  pkgs ? import <nixpkgs> { },
}:

pkgs.stdenv.mkDerivation rec {
  # Use 'rec' to easily refer to pname/version
  pname = "interactive-merge";
  version = "1.0"; # Or any version you like

  # Use the current directory containing default.nix and the script as source
  src = ./.;

  # Runtime dependencies: Commands the script calls
  # These will be available in the PATH when the script runs
  # stdenv provides bash and basic utils, but explicitly listing is clearer
  # and ensures the right versions are used.
  propagatedBuildInputs = [
    pkgs.bashInteractive # Ensures the right bash is used for shebang/runtime
    pkgs.coreutils # Provides: readlink, dirname, mkdir, rm, mv, test ([)
    pkgs.findutils # Provides: find
  ];

  # Build phase is not needed for a simple script

  # Install phase: Copy the script to the output directory
  installPhase = ''
    runHook preInstall # Standard hook

    # Create the destination directory
    install -d $out/bin

    # Copy the script, make it executable (-m755), and name it 'interactive-mv'
    install -Dm755 $src/interactive-mv.sh $out/bin/interactive-mv

    runHook postInstall # Standard hook
  '';

  # Optional: Metadata about the package
  meta = with pkgs.lib; {
    description = "Interactively merges contents of one directory into another";
    homepage = "https://example.com/your-repo"; # Optional: Replace with actual URL
    license = licenses.mit; # Choose an appropriate license (e.g., licenses.gpl3)
    platforms = platforms.unix; # Should work on most Unix-like systems
    # maintainers = [ maintainers.your_github_handle ]; # Optional
  };
}
