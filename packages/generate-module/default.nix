{ pkgs ? import <nixpkgs> { }
, lib
, stdenv
, python3
}:

python3.pkgs.buildPythonApplication {
  pname = "generate-module";
  version = "0.1.0";
  format = "other";

  src = ./.;

  dontUnpack = true;

  buildInputs = [ python3 ];

  installPhase = let
    script = ./generate-module.py;
  in ''
    mkdir -p $out/bin
    cp ${script} $out/bin/generate-module
    chmod +x $out/bin/generate-module
  '';

  meta = with lib; {
    description = "Generate NixOS module templates";
    license = licenses.mit;
    platforms = platforms.all;
  };
}
