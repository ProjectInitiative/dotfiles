# context-mode — MCP server + agent adapters (omp/pi/claude/codex/…).
#
# Installed from the npm tarball (upstream ships prebuilt artifacts; their
# build is just tsc + rolldown bundling). Self-contained for our use paths:
# the omp adapter and server bundle import only node builtins + relative
# paths, and the SQLite engine lazy-selects bun:sqlite / node:sqlite
# (>=22.5) — better-sqlite3 (native addon) is only a last-resort fallback
# we never hit. Zero node_modules needed at runtime → no buildNpmPackage.
#
# Wiring (see modules/home/cli-apps/omp): the omp adapter symlink loads via
# realpath so its relative imports stay inside this store path; the MCP
# server runs under nixpkgs bun.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation {
  pname = "context-mode";
  version = "1.0.169";

  src = fetchurl {
    url = "https://registry.npmjs.org/context-mode/-/context-mode-1.0.169.tgz";
    hash = "sha256-CcQeTPd7IVZsdrjqL9vX89gjBV/uLwLCFm/Vu1ddryw=";
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
