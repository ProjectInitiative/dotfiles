# Deckcraft: Presentations and slide shows (clean-room PowerPoint-style) — open-source, pure Rust (storytold ArtCraft family).
# Built from the pinned upstream release; builds BOTH native binaries (deckcraft + deckcraft-cli).
# The workspace vendors storytold egui/winit (+ craft-libs) via [patch.crates-io]:
# cargoLock.outputHashes pins those checkouts; unusedPatches strips
# [[patch.unused]] patch lines that break offline vendoring (cargo validates
# every patch location, but fetchcargo cannot vendor crates outside
# [[package]]).
{
  lib,
  stdenv,
  rustPlatform,
  pkgs, # for the pinned rust toolchain (craft-libs needs cargo >= 1.96)
  fetchFromGitHub,
  makeWrapper,
  pkg-config,
  autoPatchelfHook,
  alsa-lib,
  dbus,
  libGL,
  vulkan-loader,
  wayland,
  libxkbcommon,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxrandr,
  libxrender,
  libxext,
}:

let
  appVar = lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] "deckcraft");
  # [[patch.unused]] crates: <crate-version> -> the Cargo.toml patch line key.
  unusedPatches = {
    "egui_demo_lib-0.37.0" = "egui_demo_lib";
    "egui_extras-0.37.0" = "egui_extras";
    "egui_inspection-0.37.0" = "egui_inspection";
    "egui_system_font_provider-0.37.0" = "egui_system_font_provider";
  };
  craftRustPlatform = pkgs.makeRustPlatform {
    cargo = pkgs.rust-bin.stable."1.99.0".minimal;
    rustc = pkgs.rust-bin.stable."1.99.0".minimal;
  };
in
craftRustPlatform.buildRustPackage rec {
  pname = "deckcraft";
  version = "0.15.0";

  # Bump: update version/rev/hash (a stale hash names the new one in the
  # error) and refresh cargoLock.outputHashes + unusedPatches from the new
  # Cargo.lock.
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "deckcraft";
    rev = "3e178d8f5a59c787a6a53a7ed0f052b3e4a1489f"; # v0.15.0 (2026-11-03)
    hash = "sha256-ffMDpDziPZ18qa7hHbgb67cvi5w6010o4Q3fHvanyYg=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";
  cargoLock.outputHashes = {
    "craft-fonts-build-0.1.0" = "sha256-BRkWxb796qLWtF1U1EqCZFa8h1YCuoAZcXrVWMN8MEY=";
    "craft-i18n-0.1.0" = "sha256-BRkWxb796qLWtF1U1EqCZFa8h1YCuoAZcXrVWMN8MEY=";
    "craft-media-0.1.0" = "sha256-BRkWxb796qLWtF1U1EqCZFa8h1YCuoAZcXrVWMN8MEY=";
    "craft-pdf-0.1.0" = "sha256-BRkWxb796qLWtF1U1EqCZFa8h1YCuoAZcXrVWMN8MEY=";
    "craft-ui-0.1.0" = "sha256-BRkWxb796qLWtF1U1EqCZFa8h1YCuoAZcXrVWMN8MEY=";
    "craft-update-0.1.0" = "sha256-BRkWxb796qLWtF1U1EqCZFa8h1YCuoAZcXrVWMN8MEY=";
    "ecolor-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "eframe-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "egui-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "egui-wgpu-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "egui-winit-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "egui_glow-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "egui_kittest-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "emath-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "epaint-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "epaint_default_fonts-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "krilla-0.8.2" = "sha256-BRkWxb796qLWtF1U1EqCZFa8h1YCuoAZcXrVWMN8MEY=";
    "winit-0.30.13" = "sha256-+67bk7cqhM5VHqROL3PeghmhKJvlPIxhU73ay45vaxw=";
  };

  cargoBuildFlags = [
    "-p"
    "deckcraft"
    "-p"
    "deckcraft-cli"
  ];
  cargoInstallFlags = [
    "-p"
    "deckcraft"
    "-p"
    "deckcraft-cli"
  ];
  doCheck = false;

  # Strip [[patch.unused]] [patch.crates-io] lines (see header note).
  postPatch = lib.concatStrings (
    lib.mapAttrsToList (_v: crate: ''
      sed -i '/^${crate} = { git = "https:\/\/github.com\/storytold\//d' Cargo.toml
    '') unusedPatches
  );

  env = {
    "DECKCRAFT_BUILD_SHA" = "3e178d8f5a59c787a6a53a7ed0f052b3e4a1489f";
    "DECKCRAFT_BUILD_DATE" = "2026-11-03";
  };

  nativeBuildInputs = [
    pkg-config
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    alsa-lib
    stdenv.cc.cc.lib
  ];
  runtimeDependencies = [
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

  postFixup = ''
    for bin in $out/bin/*; do
      var="$(basename "$bin" | tr 'a-z-' 'A-Z_')_SKIP_LIB_CHECK"
      if grep -qa "$var" "$bin"; then
        wrapProgram "$bin" --set-default "$var" 1
      fi
    done
  '';

  meta = {
    description = "Presentations and slide shows (clean-room PowerPoint-style), built from source";
    homepage = "https://github.com/storytold/deckcraft";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "deckcraft";
    platforms = lib.platforms.linux;
  };
}
