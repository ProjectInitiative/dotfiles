{
  pkgs ? import <nixpkgs> { },
}:

let
  hurry-filesize = (import ./common.nix) { inherit pkgs; };

  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      psutil
      requests
      hurry-filesize
    ]
  );
in
pkgs.mkShell {
  name = "health-reporter-dev";
  buildInputs = [
    pythonEnv
    pkgs.makeWrapper
    pkgs.util-linux
    pkgs.smartmontools
    pkgs.coreutils
    pkgs.iproute2
  ];

  # Optional: Set environment variables if needed
  shellHook = ''
    echo "Welcome to the health-reporter development shell!"
    echo "Python environment and dependencies are ready."
  '';
}
