{
  lib,
  stdenvNoCC,
  fetchurl,
}:

# Pinned jadx-headless-mcp bridge JAR consumed by rea-agents via
# REA_JADX_MCP_JAR. REA pins an exact audited release (see
# rea-agents dist/android/JadxRelease.js) and refuses to download it;
# this derivation supplies the caller-supplied JAR.
stdenvNoCC.mkDerivation {
  pname = "jadx-headless-mcp";
  version = "0.7.1";

  src = fetchurl {
    url = "https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar";
    hash = "sha256-bl6s9QC2QpK/tzxJeXwZWPbuRGRuQ+hoA5rn/rVz/3U=";
  };

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 $src $out/share/java/jadx-headless-mcp-0.7.1-all.jar
    runHook postInstall
  '';

  meta = {
    description = "Headless jadx MCP bridge JAR for REA's Android provider";
    homepage = "https://github.com/1013503897/jadx-headless-mcp";
    license = lib.licenses.unfree; # upstream has no explicit license
    platforms = lib.platforms.all;
  };
}
