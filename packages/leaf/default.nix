{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  # Upstream tags releases without a "v" prefix.
  pname = "leaf";
  version = "1.28.3";

  src = fetchFromGitHub {
    owner = "RivoLink";
    repo = "leaf";
    rev = version;
    hash = "sha256-C37w35/PvokDEMaIwgSJ9GtAKkYRi1vNP7BfdTwTFCo=";
  };

  cargoHash = "sha256-OaG6LXKG2kda/Q1/jEBtetUGaX7YC8KwgI+MAd3Q9yg=";

  # The binary is named "leaf" via [[bin]] in Cargo.toml (crate is
  # leaf-markdown-viewer, published on crates.io under that name).
  meta = with lib; {
    description = "Terminal Markdown previewer with a GUI-like experience";
    homepage = "https://github.com/RivoLink/leaf";
    changelog = "https://github.com/RivoLink/leaf/blob/${version}/CHANGELOG.md";
    license = licenses.mit;
    mainProgram = "leaf";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
