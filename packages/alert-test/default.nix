{
  lib,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "alert-test";
  version = "1.0.0";

  src = ./.;

  pyproject = true;
  build-system = [ python3Packages.setuptools ];

  meta = with lib; {
    description = "Infra-Alert-Tester framework to trigger monitoring alerts";
    license = licenses.mit;
    maintainers = [ ];
  };
}
