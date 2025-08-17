{
  pkgs ? import <nixpkgs> { },
}:
pkgs.stdenv.mkDerivation rec {
  pname = "img-key-injector";
  version = "1.0";
  src = ./.;
  
  nativeBuildInputs = [ pkgs.makeWrapper ];
  
  buildInputs = [
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.util-linux    # provides losetup, mount, umount
    pkgs.parted        # provides partprobe
    pkgs.e2fsprogs     # provides blkid (part of util-linux in some cases)
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
      --prefix PATH : ${pkgs.e2fsprogs}/bin
    
    runHook postInstall
  '';
  
  meta = with pkgs.lib; {
    description = "Injects SSH host keys into a NixOS image using loop mounting";
    longDescription = ''
      A tool to inject pre-generated SSH host keys into NixOS disk images
      without requiring virtualization. Uses Linux loop devices to mount
      the image directly and copy keys with proper permissions.
      
      Must be run with root privileges for loop mounting operations.
    '';
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
