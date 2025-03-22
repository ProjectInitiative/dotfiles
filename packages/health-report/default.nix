{ pkgs ? import <nixpkgs> { } }:

let
  hurry-filesize = pkgs.python3Packages.buildPythonPackage {
    pname = "hurry.filesize";
    version = "0.9";
    src = pkgs.fetchPypi {
      pname = "hurry.filesize";
      version = "0.9";
      sha256 = "sha256-9TaDKa2++GrM07yUkFIjQLt5JgRVromxpCwQ9jgBuaY="; # You may need to update this
    };
    doCheck = false;
  };

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    psutil
    requests
    hurry-filesize
  ]);
in
pkgs.stdenv.mkDerivation {
  name = "health-reporter";
  src = ./.;
  buildInputs = [
    pythonEnv
    pkgs.makeWrapper
  ];
  installPhase = ''
    mkdir -p $out/bin
    install -Dm755 health-report.py $out/bin/health-report
    wrapProgram $out/bin/health-report \
      --prefix PATH : ${pkgs.lib.makeBinPath [
        pkgs.smartmontools
        pkgs.coreutils
        pkgs.iproute2
      ]}
  '';
}
