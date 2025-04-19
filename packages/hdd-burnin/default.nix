# default.nix
{
  pkgs ? import <nixpkgs> { },
}:

pkgs.stdenv.mkDerivation rec { # Use 'rec' to easily refer to pname/version
  pname = "hdd-burnin";
  version = "1.0"; # Or any version you like

  # Use the current directory containing default.nix and the script as source
  src = ./.;

  # Runtime dependencies: Commands the script calls
  # These will be available in the PATH when the script runs
  propagatedBuildInputs = [
    pkgs.bashInteractive # Provides bash itself and builtins
    pkgs.coreutils       # date, sleep, mkdir, tee, echo, printf, wc, rm, cat, cut, tail, head, tr, test ([), env
    pkgs.gnugrep         # grep
    pkgs.gawk            # awk
    pkgs.gnused          # sed
    pkgs.findutils       # find
    pkgs.util-linux      # lsblk, findmnt
    pkgs.smartmontools   # smartctl
    pkgs.e2fsprogs       # badblocks
    pkgs.jq              # jq
  ];

  # Build phase is not needed for a simple script

  # Install phase: Copy the script to the output directory
  installPhase = ''
    runHook preInstall # Standard hook

    # Create the destination directory
    install -d $out/bin

    # Copy the script, make it executable (-m755), and name it 'hdd-burnin'
    install -Dm755 $src/hdd-burnin.sh $out/bin/hdd-burnin

    runHook postInstall # Standard hook
  '';

  # Optional: Metadata about the package
  meta = with pkgs.lib; {
    description = "Performs destructive HDD burn-in tests using smartctl and badblocks";
    longDescription = ''
      A script to perform HDD burn-in tests using smartctl (initial check,
      extended self-test) and badblocks (destructive write test).
      Generates detailed logs and summaries for each drive tested.

      WARNING: This script performs DESTRUCTIVE testing using 'badblocks -w'.
      ALL DATA ON SELECTED DRIVES WILL BE PERMANENTLY ERASED.
      Requires root privileges (run via sudo). Proceed with extreme caution.
    '';
    homepage = "https://example.com/your-repo"; # Optional: Replace with actual URL if you have one
    # Choose an appropriate license for your script
    # If unsure or it's proprietary, use `licenses.unfree`
    license = licenses.mit; # Example: Replace mit with your chosen license
    # This script relies on tools/access methods typically found on Linux
    platforms = platforms.linux;
    # maintainers = [ maintainers.your_github_handle ]; # Optional: Add your handle
  };
}
