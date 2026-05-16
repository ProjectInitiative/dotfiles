{
  pkgs ? import <nixpkgs> { },
}:
pkgs.stdenv.mkDerivation rec {
  pname = "nixos-image-mount";
  version = "1.0";
  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  buildInputs = [
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.gnutar
    pkgs.gzip
    pkgs.util-linux
    pkgs.parted
    pkgs.e2fsprogs
  ];

  installPhase = ''
    runHook preInstall

    install -d $out/bin
    install -Dm755 $src/nixos-image-mount.sh $out/bin/nixos-image-mount

    wrapProgram $out/bin/nixos-image-mount \
      --prefix PATH : ${pkgs.coreutils}/bin \
      --prefix PATH : ${pkgs.bashInteractive}/bin \
      --prefix PATH : ${pkgs.gnutar}/bin \
      --prefix PATH : ${pkgs.gzip}/bin \
      --prefix PATH : ${pkgs.util-linux}/bin \
      --prefix PATH : ${pkgs.parted}/bin \
      --prefix PATH : ${pkgs.e2fsprogs}/bin

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Mounts/extracts NixOS images (.img, .tar.gz, .tgz) and prints the mount point";
    longDescription = ''
      A tool for mounting or extracting NixOS disk images and printing the
      mount point path for use by other tools (e.g. img-key-injector).
      Supports .img files via loop devices and .tar.gz/.tgz/.tar via extraction.

      Use 'mount' to mount/extract, then 'umount' to clean up. For tarballs,
      pass --retar to umount to re-pack the archive.

      Must be run as root for .img operations.
    '';
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
