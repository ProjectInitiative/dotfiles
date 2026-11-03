# Materialcraft: Material library — open-source, pure Rust (storytold ArtCraft family).
# Built from the pinned upstream release; builds BOTH native binaries (materialcraft + materialcraft-cli).
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
  appVar = lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] "materialcraft");
  craftRustPlatform = pkgs.makeRustPlatform {
    cargo = pkgs.rust-bin.stable."1.99.0".minimal;
    rustc = pkgs.rust-bin.stable."1.99.0".minimal;
  };
in
craftRustPlatform.buildRustPackage rec {
  pname = "materialcraft";
  version = "0.1.0";

  # Bump: update version/rev/hash (a stale hash names the new one in the
  # error) and refresh cargoLock.outputHashes + unusedPatches from the new
  # Cargo.lock.
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "materialcraft";
    rev = "cedabf02030a3c662fda99b197ceb3ed12790ee7"; # v0.1.0 (2026-11-03)
    hash = "sha256-v95y8NIEr1G8fMJEHaQmw1eUoCcsDHousVwUJnRjnY8=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";
  cargoLock.outputHashes = {
    "craft-fonts-build-0.1.0" = "sha256-0IBVplfbCZ7UhLR/tupGrOSYZkCFA2DBbUD9Bhs6xkE=";
    "craft-i18n-0.1.0" = "sha256-0IBVplfbCZ7UhLR/tupGrOSYZkCFA2DBbUD9Bhs6xkE=";
    "craft-ui-0.1.0" = "sha256-0IBVplfbCZ7UhLR/tupGrOSYZkCFA2DBbUD9Bhs6xkE=";
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
    "winit-0.30.13" = "sha256-+67bk7cqhM5VHqROL3PeghmhKJvlPIxhU73ay45vaxw=";
  };

  cargoBuildFlags = [
    "-p"
    "materialcraft"
    "-p"
    "materialcraft-cli"
  ];
  cargoInstallFlags = [
    "-p"
    "materialcraft"
    "-p"
    "materialcraft-cli"
  ];
  doCheck = false;

  env = {
    "MATERIALCRAFT_BUILD_SHA" = "cedabf02030a3c662fda99b197ceb3ed12790ee7";
    "MATERIALCRAFT_BUILD_DATE" = "2026-11-03";
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
    description = "Material library, built from source";
    homepage = "https://github.com/storytold/materialcraft";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "materialcraft";
    platforms = lib.platforms.linux;
  };
}
