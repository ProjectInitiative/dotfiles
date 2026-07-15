{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "ketch";
  version = "0.12.0";

  src = fetchFromGitHub {
    owner = "1broseidon";
    repo = "ketch";
    rev = "v${version}";
    hash = "sha256-qp4EwQBrN0ic/gUAvBAirz03kL7Vjhs1LbKBd+uXmHA=";
  };

  vendorHash = "sha256-Kk7fY27y1ziJEMpwRUoGfslGYYQdayLDuuRvNyfiAy8=";

  ldflags = [
    "-s"
    "-w"
  ];

  doCheck = false;

  meta = with lib; {
    description = "Stateless CLI for web search, code search, library docs, and scraping";
    homepage = "https://github.com/1broseidon/ketch";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    mainProgram = "ketch";
  };
}
