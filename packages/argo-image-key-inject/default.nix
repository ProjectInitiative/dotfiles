{
  pkgs ? import <nixpkgs> { },
}:

pkgs.stdenv.mkDerivation {
  name = "argo-image-key-inject";
  src = ./.;
  installPhase = ''
    install -Dm755 argo-image-key-inject.sh $out/bin/argo-image-key-inject
  '';
  propagatedBuildInputs = [
    pkgs.openbao
    pkgs.libguestfs-with-appliance
    pkgs.guestfs-tools
    pkgs.qemu_kvm
    pkgs.ssh-to-age
    pkgs.openssh
    pkgs.awscli2
    pkgs.kubectl
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
  ];
}
