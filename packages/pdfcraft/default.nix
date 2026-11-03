# Pdfcraft: PDF editing (clean-room Acrobat-style) — open-source, pure Rust (storytold ArtCraft family).
# Built from the pinned upstream release; builds BOTH native binaries (pdfcraft + pdfcraft-cli).
# The workspace vendors storytold forks (egui/winit/craft-libs/media crates) via
# [patch.crates-io]: cargoLock.outputHashes pins those checkouts; unusedPatches
# strips [[patch.unused]] patch lines that break offline vendoring (cargo
# validates every patch location, but fetchcargo cannot vendor crates outside
# [[package]]).
{
  lib,
  stdenv,
  rustPlatform,
  pkgs, # for the pinned rust toolchain (craft crates need cargo >= 1.96)
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
  appVar = lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] "pdfcraft");
  # craft-* workspace crates need cargo >= 1.96 (default-features override
  # rule); dotfiles nixpkgs ships 1.95.0, so pin the official 1.99.0
  # toolchain (dotfiles flake carries the oxalica rust-overlay input).
  craftRustPlatform = (
    pkgs.makeRustPlatform {
      cargo = pkgs.rust-bin.stable."1.99.0".minimal;
      rustc = pkgs.rust-bin.stable."1.99.0".minimal;
    }
  );
  # [[patch.unused]] crates: <crate-version> -> the Cargo.toml patch line key.
  unusedPatches = {
    "egui_demo_lib-0.37.0" = "egui_demo_lib";
    "egui_inspection-0.37.0" = "egui_inspection";
    "egui_system_font_provider-0.37.0" = "egui_system_font_provider";
  };
in
craftRustPlatform.buildRustPackage rec {
  pname = "pdfcraft";
  version = "0.18.0";

  # Bump: update version/rev/hash (a stale hash names the new one in the
  # error) and refresh cargoLock.outputHashes + unusedPatches from the new
  # Cargo.lock.
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "pdfcraft";
    rev = "3936f93a1479366a951206fc6d3094680fe2d3dc"; # v0.18.0 (2026-11-03)
    hash = "sha256-agLr61nG0/s786ZYj2AS2uw8hhH7a20TcCEjedHyygk=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";
  cargoLock.outputHashes = {
    "craft-docpath-0.1.0" = "sha256-oEMbxXiZ/e9RhYrefEUC0gFLPlaR9LxtUWUU8coz9As=";
    "craft-fonts-build-0.1.0" = "sha256-oEMbxXiZ/e9RhYrefEUC0gFLPlaR9LxtUWUU8coz9As=";
    "craft-i18n-0.1.0" = "sha256-oEMbxXiZ/e9RhYrefEUC0gFLPlaR9LxtUWUU8coz9As=";
    "craft-keymap-0.1.0" = "sha256-oEMbxXiZ/e9RhYrefEUC0gFLPlaR9LxtUWUU8coz9As=";
    "craft-menu-0.1.0" = "sha256-oEMbxXiZ/e9RhYrefEUC0gFLPlaR9LxtUWUU8coz9As=";
    "craft-print-0.1.0" = "sha256-oEMbxXiZ/e9RhYrefEUC0gFLPlaR9LxtUWUU8coz9As=";
    "craft-quit-0.1.0" = "sha256-oEMbxXiZ/e9RhYrefEUC0gFLPlaR9LxtUWUU8coz9As=";
    "craft-ui-0.1.0" = "sha256-oEMbxXiZ/e9RhYrefEUC0gFLPlaR9LxtUWUU8coz9As=";
    "craft-update-0.1.0" = "sha256-oEMbxXiZ/e9RhYrefEUC0gFLPlaR9LxtUWUU8coz9As=";
    "craft-winprint-gdi-0.1.0" = "sha256-n1pcNaBGrnvSsE5MedeSRczJOMhfmF/LGFiiDTrG1GM=";
    "ecolor-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "eframe-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "egui-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "egui-wgpu-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "egui-winit-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "egui_extras-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "egui_glow-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "egui_kittest-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "emath-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "epaint-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "epaint_default_fonts-0.37.0" = "sha256-xzgBk6K1X/MZ8WUlIdy+r/0cf1FDkhJJuwQHZX+WY9U=";
    "winit-0.30.13" = "sha256-+67bk7cqhM5VHqROL3PeghmhKJvlPIxhU73ay45vaxw=";
    "winprint-0.2.1" = "sha256-wnz/VbqQ3j/x1PEq6Elxu/oSjVqdONfqQmZ31NsTIIc=";
  };

  cargoBuildFlags = [
    "-p"
    "pdfcraft"
    "-p"
    "pdfcraft-cli"
  ];
  cargoInstallFlags = [
    "-p"
    "pdfcraft"
    "-p"
    "pdfcraft-cli"
  ];
  doCheck = false;

  postPatch = lib.concatStrings (
    lib.mapAttrsToList (_v: crate: ''
      sed -i '/^${crate} = { git = "https:\/\/github.com\/storytold\//d' Cargo.toml
    '') unusedPatches
  );

  env = {
    "PDFCRAFT_BUILD_SHA" = "3936f93a1479366a951206fc6d3094680fe2d3dc";
    "PDFCRAFT_BUILD_DATE" = "2026-11-03";
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
    description = "PDF editing (clean-room Acrobat-style), built from source";
    homepage = "https://github.com/storytold/pdfcraft";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "pdfcraft";
    platforms = lib.platforms.linux;
  };
}
