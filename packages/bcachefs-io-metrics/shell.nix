{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  name = "bcachefs-io-metrics-dev";
  buildInputs = [
    pkgs.python3
  ];

  # Set environment variables if needed
  shellHook = ''
    echo "Welcome to the bcachefs-io-metrics development shell!"
    echo "Python environment and dependencies are ready."
  '';
}
