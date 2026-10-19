# SolidCraft (tangency-labs) — open-source parametric 3D CAD app in pure Rust.
#
# Single package, both native binaries from the pinned release source:
#   solidcraft      GUI (apps/solidcraft)
#   solidcraft-cli  headless CLI (apps/solidcraft-cli, + solvecraft-cli alias)
# (apps/solidcraft-web is wasm — out of scope.)
#
# Cargo.lock pins every dependency; the vendored truck/matext fixes reach the
# build through [patch.crates-io] path entries in the workspace Cargo.toml,
# all inside the fetched tree — so the lock file alone suffices: no cargoHash,
# no outputHashes (upstream has no git dependencies).
#
# Runtime model mirrors upstream's own flake.nix: the binaries link only
# glibc/libgcc and dlopen() their platform stack (winit -> the Wayland/X11
# client libraries, wgpu -> the EGL/Vulkan loaders, rfd -> libdbus for
# xdg-desktop-portal), so that set goes on the wrapper's LD_LIBRARY_PATH
# rather than via patchelf — no autoPatchelfHook, which also keeps this
# package eval-safe on non-Linux snowfall channels. The Mesa/Vulkan drivers
# themselves come from the system (/run/opengl-driver on NixOS), not from
# this package; XDG_DATA_DIRS is defaulted so the loaders find the driver's
# ICD and EGL-vendor descriptions there, plus $out/share for desktop metadata.
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  dbus,
  libGL,
  vulkan-loader,
  wayland,
  libxkbcommon, # provides libxkbcommon-x11 too
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxrandr,
  libxrender,
  libxext,
}:

let
  # dlopen()ed runtime stack — mirrors upstream flake.nix `runtimeLibs`.
  runtimeLibs = [
    dbus
    libGL
    vulkan-loader
    wayland
    libxkbcommon
    libx11
    libxcb
    libxcursor
    libxi
    libxrandr
    libxrender
    libxext
  ];
  driverLibDir = "/run/opengl-driver/lib";
  driverShareDir = "/run/opengl-driver/share";
  libraryPath = lib.makeLibraryPath runtimeLibs;
in
rustPlatform.buildRustPackage rec {
  pname = "solidcraft";
  version = "0.15.0";

  # Bump by fetching github:tangency-labs/solidcraft/v<new>: update version,
  # rev (the tag's commit) and hash (the failed build names the right one).
  src = fetchFromGitHub {
    owner = "tangency-labs";
    repo = "solidcraft";
    rev = "fa691707c224cae580c42201ed3a22d5e4b8c716"; # v0.15.0 (2026-10-17)
    hash = "sha256-8R3j1s7vxyOxrOnjcLmzkmRObpifGj7NzOGzGuA4OU0=";
  };

  # Upstream requires rust >= workspace.package.rust-version (1.95 at
  # v0.15.0); the dotfiles nixpkgs pin satisfies that. If a future release
  # needs a newer rustc than nixpkgs carries, pin an oxalica rust-overlay
  # for this package (see artcraft's pdfcraft for the pattern).
  cargoLock.lockFile = "${src}/Cargo.lock";

  # Both native binaries, as upstream's flake builds them.
  cargoBuildFlags = [
    "-p"
    "solidcraft"
    "-p"
    "solidcraft-cli"
  ];
  cargoInstallFlags = [
    "-p"
    "solidcraft"
    "-p"
    "solidcraft-cli"
  ];
  # `cargo xtask ci` is the test gate (it wants a wasm target and a GPU); the
  # sandbox has neither — we validate by running.
  doCheck = false;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = lib.optionals stdenv.isLinux runtimeLibs;

  # Same desktop metadata upstream's flake and Linux packages install.
  postInstall = lib.optionalString stdenv.isLinux ''
    install -Dm644 $src/assets/platforms/linux/ai.storyteller.solidcraft.desktop \
      $out/share/applications/ai.storyteller.solidcraft.desktop
    install -Dm644 $src/assets/platforms/linux/ai.storyteller.solidcraft.mime.xml \
      $out/share/mime/packages/ai.storyteller.solidcraft.xml
    for size in 16 24 32 48 64 128 256 512; do
      icon=$out/share/icons/hicolor/''${size}x''${size}/apps/ai.storyteller.solidcraft.png
      mkdir -p "$(dirname "$icon")"
      install -m644 $src/assets/icons/app/linux/exports/hicolor/''${size}x''${size}/apps/ai.storyteller.solidcraft.png "$icon"
    done
  '';

  # The app reaches the window through dlopen'd libraries, so the packaged
  # binaries need the LD_LIBRARY_PATH/XDG_DATA_DIRS upstream's devshell
  # exports. --set-default then --prefix keeps the session's existing
  # XDG_DATA_DIRS while guaranteeing ours come first.
  postFixup = lib.optionalString stdenv.isLinux ''
    for bin in $out/bin/*; do
      wrapProgram "$bin" \
        --prefix LD_LIBRARY_PATH : "${libraryPath}:${driverLibDir}" \
        --set-default XDG_DATA_DIRS /usr/local/share:/usr/share \
        --prefix XDG_DATA_DIRS : "$out/share:${driverShareDir}"
    done
  '';

  meta = {
    description = "Rust-native parametric 3D CAD app (GUI + headless CLI), built from source";
    homepage = "https://github.com/tangency-labs/solidcraft";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "solidcraft";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
