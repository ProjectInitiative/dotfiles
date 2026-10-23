{
  namespace,
  pkgs,
  ...
}:
pkgs.mkShell {
  packages = [
    # Provisioning CLI: injects SSH host keys into disk images via guestfish
    # and converts them with qemu-img. Host-side tool — not part of any device
    # toplevel (see modules/home/security/sops/default.nix for why).
    pkgs.${namespace}.sops-hostkey-tool
  ];
}
