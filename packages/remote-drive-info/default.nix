{
  pkgs ? import <nixpkgs> { },
}:
pkgs.stdenv.mkDerivation {
  name = "remote-drive-info";
  src = ./.;
  installPhase = ''
    install -Dm755 remote-drive-info.py $out/bin/remote-drive-info
  '';
  propagatedBuildInputs = [
    pkgs.python3
    pkgs.openssh
  ];
}
