{
  pkgs ? import <nixpkgs> { },
}:

pkgs.stdenv.mkDerivation {
  name = "sops-hostkey-tool";
  src = ./.;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  installPhase = ''
    install -Dm755 sops-hostkey-tool.py $out/bin/sops-hostkey-tool
    wrapProgram $out/bin/sops-hostkey-tool \
      --prefix PATH : ${pkgs.lib.makeBinPath [
        (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
        pkgs.libguestfs-with-appliance
        pkgs.guestfs-tools
        pkgs.qemu_kvm
        pkgs.ssh-to-age
        pkgs.openssh
        pkgs.openbao
        pkgs.awscli2
        pkgs.kubectl
        pkgs.coreutils
      ]}
  '';
}
