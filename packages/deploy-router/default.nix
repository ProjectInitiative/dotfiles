{
  lib,
  python3Packages,
  openssh,
  nixos-rebuild,
}:

python3Packages.buildPythonApplication {
  pname = "deploy-router";
  version = "1.0.0";

  format = "other";

  src = ./.;

  propagatedBuildInputs = [
    openssh
    nixos-rebuild
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp deploy-router.py $out/bin/deploy-router
    chmod +x $out/bin/deploy-router
  '';

  meta = with lib; {
    description = "Deployment script for NixOS routers with failsafe rollback";
    license = licenses.mit;
    maintainers = [ ];
  };
}
