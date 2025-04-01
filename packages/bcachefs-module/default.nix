{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel ? null,
  kmod,
  namespace,
  ...
}:

let
  with-meta = lib.${namespace}.override-meta {
    platforms = lib.platforms.linux;
    broken = false;
  };

  bcachefs-module = stdenv.mkDerivation rec {
    pname = "bcachefs-module";
    version = "unstable-latency_debug";

    src = fetchFromGitHub {
      owner = "koverstreet";
      repo = "bcachefs";
      rev = "latency_debug";
      # This hash is placeholder and will need to be updated with the actual hash from the build error
      hash = lib.fakeSha256; 
    };

    nativeBuildInputs = kernel.moduleBuildDependencies;
    
    makeFlags = [
      "KERNELRELEASE=${kernel.modDirVersion}"
      "KERNEL_DIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "INSTALL_MOD_PATH=$(out)"
    ];

    preBuild = ''
      cd fs/bcachefs
      # Some out-of-tree modules require preparing the kernel tree first
      make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build modules_prepare
    '';

    buildPhase = ''
      make -j$NIX_BUILD_CORES
    '';

    installPhase = ''
      mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
      cp bcachefs.ko $out/lib/modules/${kernel.modDirVersion}/extra/
    '';

    meta = with lib; {
      description = "bcachefs filesystem as a loadable kernel module";
      homepage = "https://bcachefs.org/";
      license = licenses.gpl2;
      platforms = platforms.linux;
      maintainers = with maintainers; [ ];
    };
  };
in
with-meta bcachefs-module
