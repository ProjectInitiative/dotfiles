{
  pkgs ? import <nixpkgs> { },
}:

pkgs.stdenv.mkDerivation {
  name = "bcachefs-io-metrics";
  src = ./.;
  installPhase = ''
    install -Dm755 bcachefs-io-metrics.py $out/bin/bcachefs-io-metrics
  '';
  propagatedBuildInputs = [
    pkgs.python3
  ];
}
