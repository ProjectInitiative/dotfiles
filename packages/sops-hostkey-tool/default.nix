{
  pkgs ? import <nixpkgs> { },
}:
let
  pythonDeps =  pkgs.python3.withPackages (ps: [
    ps.pyyaml
  ]);
in
pkgs.stdenv.mkDerivation {
  name = "sops-hostkey-tool";
  src = ./.;
  installPhase = ''
    install -Dm755 sops-hostkey-tool.py $out/bin/sops-hostkey-tool
  '';
  propagatedBuildInputs = [
    pythonDeps
    pkgs.ssh-to-age
    pkgs.age
    pkgs.sops
  ];
}
