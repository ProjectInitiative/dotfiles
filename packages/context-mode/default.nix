# context-mode — MCP server + agent adapters (pi/omp/claude/codex/…).
#
# Installed from the npm tarball (upstream ships prebuilt bundles; their
# build is bundling + zero runtime deps). 2.x layout: pi extension at
# pi/index.js (omp/index.js re-exports it with the omp agent id), MCP
# server at server.mjs — both import only node builtins and use
# node:sqlite (needs node >=24, system ships 26). Zero node_modules →
# no buildNpmPackage.
#
# Wiring (see modules/home/suites/ai): the pi extension source symlink
# loads via realpath so its relative imports stay inside this store path;
# the MCP server runs under nixpkgs node.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation {
  pname = "context-mode";
  version = "2.2.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/context-mode/-/context-mode-2.2.1.tgz";
    hash = "sha256-LoIwmnZFupDyv6R+l4XkwK5g/kfuKhydG/bm9dmGtI4=";
  };

  # npm tarballs unpack with a package/ root
  sourceRoot = "package";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r . $out/
    runHook postInstall
  '';

  meta = {
    description = "MCP plugin that saves 98% of your context window — sandboxed code execution in 11 languages, FTS5 knowledge base with BM25 ranking";
    homepage = "https://github.com/mksglu/context-mode";
    # Elastic-2.0: source-available, redistribution-restricted; fine for
    # personal/internal use, which is all this derivation is for.
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
  };
}
