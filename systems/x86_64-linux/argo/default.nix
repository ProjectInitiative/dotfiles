{
  lib,
  pkgs,
  inputs,
  namespace,
  config,
  options,
  modulesPath,
  ...
}:
with lib;
with lib.${namespace};
{

  projectinitiative = {
    hosts = {
      # nixFromDataDisk: the LIVE VM binds /nix from /data/nix in the
      # INITRD (ordered after /data), so stage-1 sops sees the store
      # rebuilds write into — no extra VM disk, no stage-2 flip. The baked
      # image (x86_64-kubevirt/argo-image) keeps the default bootstrap
      # bind-flip because the fstab bind would hide the image store before
      # seeding could run (fresh /data = no init).
      argo = {
        enable = true;
        nixFromDataDisk = true;
      };
    };
  };

  networking.hostName = "argo";

  # Tailscale for stable access (argo.taildeab2.ts.net) regardless of which
  # pod IP the masquerade hands out. Live host only — NOT the image build,
  # so bake boots never register ephemeral nodes into the tailnet.
  projectinitiative.networking.tailscale = {
    enable = true;
    ephemeral = false; # stable identity; auth key from sops tailscale_auth_key
  };

  # Live-rebuild target (nixos-rebuild --target-host kylepzak@<pod-ip>).
  # The kubevirt image build gets root fs + grub from the nixos-generators
  # format module; the live system needs them stated here (same VM disk).
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  boot.loader.grub.device = "/dev/vda";
}
