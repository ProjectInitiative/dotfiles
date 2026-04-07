{
  pkgs ? import <nixpkgs> { },
}:
let
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.torch
    ps.prometheus-client
  ]);
in
pkgs.stdenv.mkDerivation {
  name = "npu-analyzer";
  src = ./.;
  installPhase = ''
    mkdir -p $out/bin
    install -Dm755 npu-analyzer.py $out/bin/npu-analyzer

    # Wrap the script to use the environment with packages
    sed -i 's|#!/usr/bin/env python3|#!${pythonEnv}/bin/python|' $out/bin/npu-analyzer
  '';
}
