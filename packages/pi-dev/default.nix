{
  pkgs,
  lib,
  stdenv,
}:

stdenv.mkDerivation {
  pname = "pi-dev";
  version = "0.1.0";
  src = ./.;
  installPhase = ''
    install -Dm755 pi-dev.sh $out/bin/pi-dev
  '';
  meta = with lib; {
    description = "Rapid extension development for pi-coding-agent — deploy extensions to writable path for /reload iteration";
    longDescription = ''
      Copies extensions from the Nix-managed source directory to ~/.pi/agent/extensions/
      as writable files, enabling fast edit → /reload → test cycles without rebuilding Nix.

      Usage:
        pi-dev <name>            Deploy extension for /reload
        pi-dev <name> --edit     Deploy + open in $EDITOR
        pi-dev <name> --watch    Watch source, auto-deploy on save
        pi-dev --list            Show available extensions
    '';
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [ ];
  };
}
