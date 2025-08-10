{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  fetchNpmDeps,
  writeShellApplication,
  cacert,
  curl,
  gnused,
  jq,
  nix-prefetch-github,
  prefetch-npm-deps,
  gitUpdater,
  git,
}:

buildNpmPackage (finalAttrs: {
  pname = "qwen-code";
  version = "v0.0.5";

  src = fetchFromGitHub {
    owner = "QwenLM";
    repo = "qwen-code";
    tag = "${finalAttrs.version}";
    hash = "sha256-/PuykGiXpjk2Fp1Sif59hvOIepZ7KcJRvL/9RMatQJA=";
  };

  npmDeps = fetchNpmDeps {
    inherit (finalAttrs) src;
    hash = "sha256-HzrN549MfI+TN7BKssisIsga7udGKvextruzuoLq8M4=";
  };

  nativeBuildInputs = [ git ];

  buildPhase = ''
    runHook preBuild
    npm run bundle
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib
    cp -rL node_modules $out/lib/
    cp -r bundle $out/lib/
    ln -s $out/lib/bundle/gemini.js $out/bin/qwen
    runHook postInstall
  '';

  postInstall = ''
    chmod +x $out/bin/qwen
  '';

  passthru.updateScript = gitUpdater { };

  meta = {
    description = "qwen-code is a coding agent that lives in digital world. ";
    homepage = "https://github.com/QwenLM/qwen-code";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ ];
    platforms = lib.platforms.all;
    mainProgram = "qwen";
  };
})
