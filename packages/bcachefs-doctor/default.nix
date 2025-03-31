{
  pkgs ? import <nixpkgs> { },
}:

pkgs.stdenv.mkDerivation {
  name = "bcachefs-doctor";
  src = ./.;
  installPhase = ''
    install -Dm755 bcachefs-doctor.py $out/bin/bcachefs-doctor
  '';
  propagatedBuildInputs = [
    pkgs.python3
    pkgs.util-linux
    pkgs.coreutils
    pkgs.iproute2
    pkgs.findutils
    pkgs.bcachefs-tools
  ];
}
