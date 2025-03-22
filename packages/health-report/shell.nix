{ pkgs ? import <nixpkgs> { } }:

let
  hurry-filesize = pkgs.python3Packages.buildPythonPackage {
    pname = "hurry.filesize";
    version = "0.9";
    src = pkgs.fetchPypi {
      pname = "hurry.filesize";
      version = "0.9";
      sha256 = "sha256-9TaDKa2++GrM07yUkFIjQLt5JgRVromxpCwQ9jgBuaY="; # Update if necessary
    };
    doCheck = false;
  };

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    psutil
    requests
    hurry-filesize
  ]);
in
pkgs.mkShell {
  name = "health-reporter-dev";
  buildInputs = [
    pythonEnv
    pkgs.makeWrapper
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
