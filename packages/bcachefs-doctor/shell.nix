{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  name = "bcachefs-doctor-dev";
  buildInputs = [
    pkgs.python3
    pkgs.util-linux
    pkgs.coreutils
    pkgs.iproute2
    pkgs.bcachefs-tools
  ];

  # Set environment variables if needed
  shellHook = ''
    echo "Welcome to the bcachefs-doctor development shell!"
    echo "Python environment and dependencies are ready."
  '';
}
