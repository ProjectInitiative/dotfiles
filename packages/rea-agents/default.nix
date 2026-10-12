{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  gitUpdater,
}:

buildNpmPackage (finalAttrs: {
  pname = "rea-agents";
  version = "6.4.0";

  src = fetchFromGitHub {
    owner = "morluto";
    repo = "rea";
    tag = "rea-agents-${finalAttrs.version}";
    hash = "";
  };

  npmDeps = fetchNpmDeps {
    inherit (finalAttrs) src;
    hash = "";
  };

  # The repo ships prebuilt skills/bridges; the turbo "build" script only
  # regenerates artifacts that are already committed. Skip it.
  dontNpmBuild = true;

  passthru.updateScript = gitUpdater { };

  meta = {
    description = "REA: Reverse Engineer Anything — MCP server + CLI for reverse engineering binaries, managed code, and runtime behavior";
    homepage = "https://github.com/morluto/rea";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    mainProgram = "rea";
  };
})
