{
  lib,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "alert-test";
  version = "1.0.0";

  src = ./.;

  format = "other";

  installPhase = ''
    install -Dm755 alert_test.py $out/bin/alert-test
  '';

  meta = with lib; {
    description = "Infra-Alert-Tester framework to trigger monitoring alerts";
    license = licenses.mit;
    maintainers = [ ];
  };
}
