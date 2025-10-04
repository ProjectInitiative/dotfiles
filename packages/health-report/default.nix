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
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.util-linux
          pkgs.smartmontools
          pkgs.coreutils
          pkgs.iproute2
        ]
      }
  '';
}
