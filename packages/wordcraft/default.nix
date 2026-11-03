# Wordcraft: Word processor (clean-room Word-style) — open-source, pure Rust (storytold ArtCraft family).
# Built from the pinned upstream release; builds BOTH native binaries (wordcraft + wordcraft-cli).
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
  appVar = lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] "wordcraft");
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
  pname = "wordcraft";
  version = "0.15.0";

  # Bump: update version/rev/hash (a stale hash names the new one in the
  # error) and refresh cargoLock.outputHashes + unusedPatches from the new
  # Cargo.lock.
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "wordcraft";
    rev = "b47079fc791595fd84bb499d64dcd3f0624ef35a"; # v0.15.0 (2026-11-03)
    hash = "sha256-AZJphQEBCkJiqAo2qus5R/LL6qTyiDODNU9yfVt8gUE=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";
  cargoLock.outputHashes = {
    "craft-atomic-0.1.0" = "sha256-cyjktjU+fsQFQaG/aKxq7xtj/mrpdLEqCjKgujCXaAE=";
    "craft-font-catalog-0.1.0" = "sha256-cyjktjU+fsQFQaG/aKxq7xtj/mrpdLEqCjKgujCXaAE=";
    "craft-font-store-0.1.0" = "sha256-cyjktjU+fsQFQaG/aKxq7xtj/mrpdLEqCjKgujCXaAE=";
    "craft-fonts-build-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "craft-i18n-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "craft-pdf-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "craft-print-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "craft-proof-0.1.0" = "sha256-YLjP7ZPC1YOgKEhk4u2om/VlNtr+VJYXaAihhNnqSHc=";
    "craft-ui-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "craft-update-0.1.0" = "sha256-BRkWxb796qLWtF1U1EqCZFa8h1YCuoAZcXrVWMN8MEY=";
    "craft-window-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "craft-winprint-gdi-0.1.0" = "sha256-n1pcNaBGrnvSsE5MedeSRczJOMhfmF/LGFiiDTrG1GM=";
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
    "krilla-0.8.2" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "winit-0.30.13" = "sha256-+67bk7cqhM5VHqROL3PeghmhKJvlPIxhU73ay45vaxw=";
    "winprint-0.2.1" = "sha256-wnz/VbqQ3j/x1PEq6Elxu/oSjVqdONfqQmZ31NsTIIc=";
  };

  cargoBuildFlags = [
    "-p"
    "wordcraft"
    "-p"
    "wordcraft-cli"
  ];
  cargoInstallFlags = [
    "-p"
    "wordcraft"
    "-p"
    "wordcraft-cli"
  ];
  doCheck = false;

  # Strip [[patch.unused]] [patch.crates-io] lines (see header note).
  postPatch = lib.concatStrings (
    lib.mapAttrsToList (_v: crate: ''
      sed -i '/^${crate} = { git = "https:\/\/github.com\/storytold\//d' Cargo.toml
    '') unusedPatches
  );

  env = {
    "WORDCRAFT_BUILD_SHA" = "b47079fc791595fd84bb499d64dcd3f0624ef35a";
    "WORDCRAFT_BUILD_DATE" = "2026-11-03";
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
    description = "Word processor (clean-room Word-style), built from source";
    homepage = "https://github.com/storytold/wordcraft";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "wordcraft";
    platforms = lib.platforms.linux;
  };
}
