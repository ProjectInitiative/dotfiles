{
  lib,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "npu-analysis";
  version = "1.0.0";

  src = ./.;

  pyproject = true;
  build-system = [ python3Packages.setuptools ];

  dependencies = with python3Packages; [
    scapy
    torch
  ];

  meta = with lib; {
    description = "NPU AI Network Analysis service using PyTorch and NFLOG";
    license = licenses.mit;
    maintainers = [ ];
  };
}
