{
  pkgs ? import <nixpkgs> { },
  lib,
  stdenv,
}:

stdenv.mkDerivation {
  name = "gen-host-key";
  src = ./.;
  installPhase = ''
    install -Dm755 gen-host-key.sh $out/bin/gen-host-key
  '';
  propagatedBuildInputs = [
    pkgs.openssh
    pkgs.ssh-to-age
  ];
  meta = with lib; {
    description = "Generate SSH host key + age public key for a host, drop into ./keys/<hostname>/";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
