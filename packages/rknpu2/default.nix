{
  lib,
  stdenv,
  fetchFromGitHub,
  autoPatchelfHook,
}:

let
  # The user-provided fetchFromGitHub expression for the rknpu2 SDK
  rknpu2-src = fetchFromGitHub {
    owner = "rockchip-linux";
    repo = "rknpu2";
    rev = "5adf7c1bd17e169e9880ccdf3b49adde925ab7f9";
    hash = "sha256-9szvZmMreyuigeAUe8gIQgBzK/f9c9IgsIUAuHNguRU=";
  };
in
stdenv.mkDerivation rec {
  pname = "rknpu2";
  version = "1.5.2";

  src = rknpu2-src;

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/include

    # --- rknnrt ---
    cp ${src}/runtime/RK3588/Linux/librknn_api/aarch64/librknnrt.so $out/lib/
    cp -r ${src}/runtime/RK3588/Linux/librknn_api/include/* $out/include/

    # --- rga ---
    cp ${src}/examples/3rdparty/rga/RK3588/lib/Linux/aarch64/librga.so $out/lib/
    cp -r ${src}/examples/3rdparty/rga/RK3588/include/* $out/include/

    runHook postInstall
  '';

  meta = with lib; {
    description = "Pre-packaged Rockchip RKNN NPU runtime libraries for RK3588 (aarch64)";
    homepage = "https://github.com/rockchip-linux/rknpu2";
    license = licenses.bsd3;
    # Allow x86_64-linux so this is visible when cross-compiling FROM x86_64 to aarch64
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
