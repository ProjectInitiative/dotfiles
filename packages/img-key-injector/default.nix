{
  pkgs ? import <nixpkgs> { },
}:

pkgs.stdenv.mkDerivation rec {
  pname = "img-key-injector";
  version = "1.0";

  src = ./.;

  propagatedBuildInputs = [
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.libguestfs # provides guestfish
  ];

  installPhase = ''
    runHook preInstall

    install -d $out/bin

    # Copy script into $out/bin, name it img-key-injector
    install -Dm755 $src/img-key-injector.sh $out/bin/img-key-injector

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Injects SSH host keys into a NixOS Raspberry Pi image using guestfish";
    longDescription = ''
      This tool mounts a NixOS image with libguestfs/guestfish and injects
      pre-generated SSH host keys into /etc/ssh inside the root partition.
      Useful for pre-populating secrets when building NixOS images for Raspberry Pi
      and other SoCs, avoiding the chicken-and-egg problem with sops-nix.
    '';
    license = licenses.mit;
    platforms = platforms.linux;
  };
}

