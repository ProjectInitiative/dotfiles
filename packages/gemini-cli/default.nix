{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nix-update-script,
}:

let
  pname = "gemini-cli";
  version = "0.1.5";
in
buildNpmPackage {
  inherit pname version;

  src = fetchFromGitHub {
    owner = "google-gemini";
    repo = "gemini-cli";
    # Currently there's no release tag, use the `package-lock.json` to see
    # what's the latest version
    rev = "121bba346411cce23e350b833dc5857ea2239f2f";
    hash = "sha256-2w28N6Fhm6k3wdTYtKH4uLPBIOdELd/aRFDs8UMWMmU=";
  };

  npmDepsHash = "sha256-yoUAOo8OwUWG0gyI5AdwfRFzSZvSCd3HYzzpJRvdbiM=";

  fixupPhase = ''
    runHook preFixup

    # Remove broken symlinks
    find $out -type l -exec test ! -e {} \; -delete 2>/dev/null || true

    mkdir -p "$out/bin"
    ln -sf "$out/lib/node_modules/@google/gemini-cli/bundle/gemini.js" "$out/bin/gemini"

    patchShebangs "$out/bin" "$out/lib/node_modules/@google/gemini-cli/bundle/"

    runHook postFixup
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "AI agent that brings the power of Gemini directly into your terminal";
    homepage = "https://github.com/google-gemini/gemini-cli";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ donteatoreo ];
    platforms = lib.platforms.all;
    mainProgram = "gemini";
  };
}
