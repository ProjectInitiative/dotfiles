{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  gitUpdater,
  pkgs,
}:

buildNpmPackage (finalAttrs: {
  pname = "rea-agents";
  version = "6.4.0";

  src = fetchFromGitHub {
    owner = "morluto";
    repo = "rea";
    tag = "rea-agents-${finalAttrs.version}";
    hash = "sha256-aAbOYpsT6QhlLAZDtVHZ1Acz6uIqrVEd4p49s/2FJgc=";
  };

  # NOTE: snowfall's package callPackage scope does not expose top-level
  # fetchNpmDeps as a formal arg — resolve it off pkgs instead.
  npmDeps = pkgs.fetchNpmDeps {
    inherit (finalAttrs) src;
    hash = "sha256-XuiMtaM/MPDkhjiHCr9dGC7WlsRBmsWepuNHRxAs3Nw=";
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
