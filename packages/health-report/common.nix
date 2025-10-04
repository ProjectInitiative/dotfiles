{ pkgs }:

pkgs.python3Packages.buildPythonPackage {
  pname = "hurry.filesize";
  version = "0.9";
  src = pkgs.fetchPypi {
    pname = "hurry.filesize";
    version = "0.9";
    sha256 = "sha256-9TaDKa2++GrM07yUkFIjQLt5JgRVromxpCwQ9jgBuaY=";
  };
  pyproject = true;
  build-system = [ pkgs.python3Packages.setuptools ];
  doCheck = false;
}
