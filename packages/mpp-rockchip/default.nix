{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  libdrm,
  libva,
}:

stdenv.mkDerivation rec {
  pname = "mpp-rockchip";
  version = "unstable-2025-03-16";

  src = fetchFromGitHub {
    owner = "tsukumijima";
    repo = "mpp-rockchip";
    rev = "750e76ec2d9287babfaf08c8bf395ebc5e8778ea";
    hash = "sha256-2Pdc7dWW9v+EIdgLV923GmSqwa11BUok3wLUYxR8flc=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    libdrm
    libva
  ];

  # Disable static library build which fails in Nix environment due to POST_BUILD logic
  # Also fix broken paths in pkg-config files
  postPatch = ''
    sed -i '/# build static library/,/add_subdirectory(legacy)/ { /add_subdirectory(legacy)/!d }' mpp/CMakeLists.txt
    sed -i '/install(TARGETS ''${MPP_STATIC}/d' mpp/CMakeLists.txt
    
    # Fix double slashes in .pc files by removing ''${prefix}/ before absolute paths
    sed -i 's|=''${prefix}/@|=@|g' pkgconfig/*.pc.cmake
  '';

  cmakeFlags = [
    "-DCMAKE_INSTALL_PREFIX=$out"
    "-DRK_PLATFORM=ON"
  ];

  enableParallelBuilding = true;

  meta = with lib; {
    description = "Rockchip Media Process Platform (MPP) userspace library";
    homepage = "https://github.com/tsukumijima/mpp-rockchip";
    license = licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
