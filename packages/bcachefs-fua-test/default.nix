{
  pkgs ? import <nixpkgs> { },
}:

pkgs.stdenv.mkDerivation {
  name = "bcachefs-fua-test";
  src = ./.;
  installPhase = ''
    install -Dm755 bcachefs-fua-test.py $out/bin/bcachefs-fua-test
  '';
  propagatedBuildInputs = [
    pkgs.python3
    pkgs.util-linux
    pkgs.nvme-cli
  ];
}
