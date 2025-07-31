{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nix-update-script,
}:

let
  pname = "gemini-cli";
  version = "0.1.15";
in
buildNpmPackage {
  inherit pname version;

  src = fetchFromGitHub {
    owner = "google-gemini";
    repo = "gemini-cli";
    # Currently there's no release tag, use the `package-lock.json` to see
    # what's the latest version
    rev = "ed1483b06f630775bf75baedda8d475dac46dc0d";
    hash = "sha256-J9pDSMsSh7FVPD61FFV2Aes3G/Vj1j5ULn9dOr+sglQ=";
  };

  npmDepsHash = "sha256-otogkSsKJ5j1BY00y4SRhL9pm7CK9nmzVisvGCDIMlU=";

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
