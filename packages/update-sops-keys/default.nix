{
  pkgs ? import <nixpkgs> { },
}:

pkgs.stdenv.mkDerivation {
  name = "update-sops-keys";
  src = ./.;
  installPhase = ''
    install -Dm755 update-sops-keys.py $out/bin/update-sops-keys
  '';
  propagatedBuildInputs = [
    pkgs.python3
    pkgs.python3Packages.pyyaml
    pkgs.age
    pkgs.sops
  ];
}
