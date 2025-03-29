{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  name = "bcachefs-fua-test-dev";
  buildInputs = [
    pkgs.python3
    pkgs.util-linux
    pkgs.nvme-cli
  ];

  # Set environment variables if needed
  shellHook = ''
    echo "Welcome to the bcachefs-fua-test development shell!"
    echo "Python environment and dependencies are ready."
  '';
}
