# nix-build -E 'with import <nixpkgs> {}; callPackage ./package.nix {}'
{ fetchFromGitHub, lib, rustPlatform, git, installShellFiles }:

rustPlatform.buildRustPackage rec {
  pname = "helix";
  version = "24.07";

  # Fetch the source code directly from the GitHub repository
  src = fetchFromGitHub {
    owner = "helix-editor";
    repo = "helix";
    rev = "57ec3b7330de3f5a7b37e766a758f13fdf3c0da5";  # Replace with the specific commit hash
    hash = "sha256-10PtZHgDq7S5n8ez0iT9eLWvAlEDtEi572yFzidLW/0=";  # Replace with the actual hash
  };

  # cargoLock = {
  #   lockFile = ./Cargo.lock;
  #   # outputHashes = {
  #   #   "hf-hub-0.3.2" = "sha256-1AcishEVkTzO3bU0/cVBI2hiCFoQrrPduQ1diMHuEwo=";
  #   #   "tree-sitter-zig-0.0.1" = "sha256-UXJCh8GvXzn+sssTrIsLViXD3TiBZhLFABYCKM+fNMQ=";
  #   # };
  # };
  # cargoHash = "sha256-Y8zqdS8vl2koXmgFY0hZWWP1ZAO8JgwkoPTYPVpkWsA=";
  cargoHash = "sha256-kxvj7f6GszuV8JQgUCGJud8EmwhgYEkK3ZQLGGR6Nc0=";

  nativeBuildInputs = [ git installShellFiles ];

  env.HELIX_DEFAULT_RUNTIME = "${placeholder "out"}/lib/runtime";

  postInstall = ''
    # not needed at runtime
    rm -r runtime/grammars/sources

    mkdir -p $out/lib
    cp -r runtime $out/lib
    installShellCompletion contrib/completion/hx.{bash,fish,zsh}
    mkdir -p $out/share/{applications,icons/hicolor/256x256/apps}
    cp contrib/Helix.desktop $out/share/applications
    cp contrib/helix.png $out/share/icons/hicolor/256x256/apps
  '';

  meta = with lib; {
    description = "Post-modern modal text editor";
    homepage = "https://helix-editor.com";
    license = licenses.mpl20;
    mainProgram = "hx";
    maintainers = with maintainers; [ danth yusdacra zowoq ];
  };
}
