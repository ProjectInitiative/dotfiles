{
  pkgs ? import <nixpkgs> { },
}:
pkgs.stdenv.mkDerivation rec {
  pname = "img-key-injector";
  version = "1.1";
  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  buildInputs = [
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.util-linux # provides losetup, mount, umount
    pkgs.parted # provides partprobe
    pkgs.e2fsprogs # provides blkid (part of util-linux in some cases)
    pkgs.openssh # provides ssh-keygen (for --generate)
    pkgs.gnutar
    pkgs.gzip
    pkgs.pigz # parallel gzip for tar.gz re-pack (falls back to gzip)
  ];

  installPhase = ''
    runHook preInstall

    install -d $out/bin
    install -Dm755 $src/img-key-injector.sh $out/bin/img-key-injector

    # Wrap with all required utilities in PATH
    wrapProgram $out/bin/img-key-injector \
      --prefix PATH : ${pkgs.coreutils}/bin \
      --prefix PATH : ${pkgs.bashInteractive}/bin \
      --prefix PATH : ${pkgs.util-linux}/bin \
      --prefix PATH : ${pkgs.parted}/bin \
      --prefix PATH : ${pkgs.e2fsprogs}/bin \
      --prefix PATH : ${pkgs.openssh}/bin \
      --prefix PATH : ${pkgs.gnutar}/bin \
      --prefix PATH : ${pkgs.gzip}/bin \
      --prefix PATH : ${pkgs.pigz}/bin

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Injects SSH host keys into NixOS disk images using loop mounting";
    longDescription = ''
      A tool to inject (or generate and inject) SSH host keys into NixOS disk
      images without requiring virtualization. Supports partitioned raw disk
      images, bare filesystem images (e.g. AVF root_part), and AVF-style
      .tar.gz archives (streamed member-wise; only root_part is extracted and
      the archive is re-packed in place).

      Must be run with root privileges for loop mounting operations.
    '';
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
