# Effectcraft: Visual effects and compositing (clean-room After Effects-style) — open-source, pure Rust (storytold ArtCraft family).
# Built from the pinned upstream release; builds BOTH native binaries (effectcraft + effectcraft-cli).
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
  appVar = lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] "effectcraft");
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
    "egui_extras-0.37.0" = "egui_extras";
    "egui_inspection-0.37.0" = "egui_inspection";
    "egui_system_font_provider-0.37.0" = "egui_system_font_provider";
  };
in
craftRustPlatform.buildRustPackage rec {
  pname = "effectcraft";
  version = "0.21.0";

  # Bump: update version/rev/hash (a stale hash names the new one in the
  # error) and refresh cargoLock.outputHashes + unusedPatches from the new
  # Cargo.lock.
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "effectcraft";
    rev = "7870b5916ae0749d497d880989683bf2946d6c8b"; # v0.21.0 (2026-11-03)
    hash = "sha256-bKKAYM4tKV3EateUKOg7PpbxfXB0xMKsXmvPQvDuK/Q=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";
  cargoLock.outputHashes = {
    "craft-docpath-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "craft-ecproj-format-0.1.0" = "sha256-aEW6WiEyi9YB/mAVdhRJ/WaPBxaIhH1wkhenPE8KLNE=";
    "craft-fonts-build-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "craft-i18n-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "craft-pdf-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "craft-quit-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "craft-ui-0.1.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
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
    "filmcraft-aac-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-ac3-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-apv-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-av1-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-avi-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-bitstream-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-cfb-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-codecs-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-color-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-dng-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-dnx-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-frame-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-geom-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-h264-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-h264enc-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-hevc-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-interchange-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-isobmff-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-matroska-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-media-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-mpa-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-mpeg2v-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-mpegts-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-mxf-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-ogg-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-opus-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-project-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-prores-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-time-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-vp8-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "filmcraft-vp9-0.8.0" = "sha256-zwGlMsfzhQT+5pbYOaxyaOAfBkm6Ocs6s8+Dnz1A+nE=";
    "hayro-jbig2-0.3.0" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "hayro-syntax-0.7.2" = "sha256-/8I9DcqtsznoYPo4ECc/rPQIal6P9gyPksrvVHDW6Mg=";
    "winit-0.30.13" = "sha256-+67bk7cqhM5VHqROL3PeghmhKJvlPIxhU73ay45vaxw=";
  };

  cargoBuildFlags = [
    "-p"
    "effectcraft"
    "-p"
    "effectcraft-cli"
  ];
  cargoInstallFlags = [
    "-p"
    "effectcraft"
    "-p"
    "effectcraft-cli"
  ];
  doCheck = false;

  postPatch = lib.concatStrings (
    lib.mapAttrsToList (_v: crate: ''
      sed -i '/^${crate} = { git = "https:\/\/github.com\/storytold\//d' Cargo.toml
    '') unusedPatches
  );

  env = {
    "EFFECTCRAFT_BUILD_SHA" = "7870b5916ae0749d497d880989683bf2946d6c8b";
    "EFFECTCRAFT_BUILD_DATE" = "2026-11-03";
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
    description = "Visual effects and compositing (clean-room After Effects-style), built from source";
    homepage = "https://github.com/storytold/effectcraft";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "effectcraft";
    platforms = lib.platforms.linux;
  };
}
