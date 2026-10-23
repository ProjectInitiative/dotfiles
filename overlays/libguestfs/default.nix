# libguestfs's installCheckPhase boots the appliance VM (guestfish `run`
# starts qemu on a 10G qcow2). On hosts without usable KVM (e.g. nested /
# sandboxed aarch64 builders) that test falls back to TCG emulation and
# effectively hangs for hours. We only use libguestfs/guestfs-tools as
# runtime deps (sops-hostkey-tool wraps guestfish), so skip the checks.
{ channels, inputs, ... }:
final: prev: {
  libguestfs = prev.libguestfs.overrideAttrs (_: {
    doCheck = false;
    doInstallCheck = false;
  });
}
