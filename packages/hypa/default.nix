# hypa — workspace mux + output compression CLI from Hypabolic
# (https://github.com/Hypabolic/Hypa). Used by pi via the @hypabolic/pi-hypa
# npm extension: tools (hypa_shell/hypa_read/...) rewrite shell commands
# through the mux host. Not in nixpkgs (FSL-1.1 license, prebuilt npm
# distribution), so we package the official linux-x64 npm tarball.
#
# Upstream layout: @hypabolic/hypa (JS meta-package with bin.js launcher)
# depends on @hypabolic/hypa-<os>-<arch> which ships the native binaries.
# We take only the linux-x64 platform tarball — it contains everything the
# meta-package would launch: hypa (CLI), hypa-attach, hypa-annotate,
# hypa-runtime, hypa-pty-host + dlopen'd libs (libmsquic, libghostty-vt,
# libtree-sitter-*, libe_sqlite3, libnuma).
#
# The tarballs target generic glibc, so:
#   - set-interpreter on the 5 ELF executables (only libm/libc needed)
#   - RPATH $ORIGIN on the executables and on libmsquic.so.2 so its
#     libcrypto.so.3 (nixpkgs openssl) and bundled libnuma.so.1 resolve.
#     dlopen'd libs are found through the loader's RPATH, so no wrappers.
# A nixpkgs aarch64-linux variant would be the same shape against
# hypa-linux-arm64-<version>.tgz if needed.
{
  lib,
  stdenv,
  fetchurl,
  patchelf,
  openssl,
}:
stdenv.mkDerivation {
  pname = "hypa";
  version = "1.0.8";

  src = fetchurl {
    url = "https://registry.npmjs.org/@hypabolic/hypa-linux-x64/-/hypa-linux-x64-1.0.8.tgz";
    hash = "sha256-4N2nbBxhOQJNCnBHIjUarUfbnDBfctPuq93bbwQaZVY=";
  };

  # npm tarballs unpack with a package/ root
  sourceRoot = "package";

  nativeBuildInputs = [ patchelf ];
  dontBuild = true;
  # Prebuilt artifacts ship with their own debug info; stripping them is
  # unnecessary work and risks breaking the .NET AOT sections.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/hypa $out/bin
    cp -r bin/* $out/lib/hypa/

    interpreter="$(cat $NIX_CC/nix-support/dynamic-linker)"
    opensslOut="${lib.makeLibraryPath [ openssl ]}"
    for exe in hypa hypa-attach hypa-annotate hypa-runtime hypa-pty-host; do
      patchelf --set-interpreter "$interpreter" $out/lib/hypa/$exe
      patchelf --set-rpath "\$ORIGIN:$opensslOut" $out/lib/hypa/$exe
    done
    # dlopen'd libmsquic needs libcrypto.so.3 from nixpkgs; libnuma is bundled.
    patchelf --set-rpath "\$ORIGIN:$opensslOut" $out/lib/hypa/libmsquic.so.2

    ln -s $out/lib/hypa/hypa $out/bin/hypa
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/hypa --version >/dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Workspace mux and local context runtime for coding agents (output compression, shell rewriting)";
    homepage = "https://github.com/Hypabolic/Hypa";
    # FSL-1.1-ALv2: functional source license, converts to Apache-2.0 after
    # the change date. Redistribution via npm tarball is the upstream
    # distribution channel; fine for personal/internal use.
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
