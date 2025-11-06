{ pkgs ? import <nixpkgs> { } }:

let
  # The user-provided fetchFromGitHub expression for the rknpu2 SDK
  rknpu2-src = pkgs.fetchFromGitHub {
    owner = "rockchip-linux";
    repo = "rknpu2";
    rev = "5adf7c1bd17e169e9880ccdf3b49adde925ab7f9";
    hash = "sha256-9szvZmMreyuigeAUe8gIQgBzK/f9c9IgsIUAuHNguRU=";
  };
in
pkgs.stdenv.mkDerivation rec {
  pname = "rknpu2";
  # The version is extracted from the SDK documentation filenames
  version = "1.5.2";

  # The source is the fetched GitHub repository
  src = rknpu2-src;

  # Use autoPatchelfHook to fix library paths in the .so files
  nativeBuildInputs = [
    pkgs.autoPatchelfHook
  ];

  # Add the C++ standard library to the build inputs. This allows autoPatchelfHook
  # to find dependencies like libstdc++.so.6 and libgcc_s.so.1.
  buildInputs = [
    pkgs.stdenv.cc.cc.lib
  ];

  # This is a pre-compiled binary package. The installPhase consists of
  # manually copying the required files from the source into the Nix store output path ($out).
  installPhase = ''
    runHook preInstall

    # Create the destination directories in the output path
    mkdir -p $out/lib $out/include

    # --- rknnrt ---
    # Copy the main rknn runtime library
    echo "Copying librknnrt.so..."
    cp ${src}/runtime/RK3588/Linux/librknn_api/aarch64/librknnrt.so $out/lib/

    # Copy all rknn headers
    echo "Copying rknn_api headers..."
    cp -r ${src}/runtime/RK3588/Linux/librknn_api/include/* $out/include/

    # --- rga ---
    # Copy the rga (Rockchip Graphics Acceleration) library
    echo "Copying librga.so..."
    cp ${src}/examples/3rdparty/rga/RK3588/lib/Linux/aarch64/librga.so $out/lib/

    # Copy all rga headers
    echo "Copying rga headers..."
    cp -r ${src}/examples/3rdparty/rga/RK3588/include/* $out/include/

    runHook postInstall
  '';

  # Add metadata for the package
  meta = with pkgs.lib; {
    description = "Pre-packaged Rockchip RKNN NPU runtime libraries for RK3588 (aarch64)";
    homepage = "https://github.com/rockchip-linux/rknpu2";
    # The license is specified in the LICENSE file in the root of the repository.
    license = licenses.bsd3;
    # This package contains aarch64 binaries and is intended for that platform.
    platforms = [ "aarch64-linux" ];
    maintainers = [ maintainers.projectinitiative ]; # Feel free to change this
  };
}

