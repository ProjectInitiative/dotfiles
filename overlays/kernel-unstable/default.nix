{ inputs, ... }:
final: prev:
let
  upstreamPkgs = import inputs.upstream {
    system = prev.stdenv.hostPlatform.system;
    # Pass configuration from the main nixpkgs to keep it consistent
    config = prev.config;
  };
in {
  # # Override kernelPackages to use upstream
  # linuxPackages_latest = upstreamPkgs.linuxPackages_latest;
  # linuxPackages_6_16   = upstreamPkgs.linuxPackages_6_16;

  # # Use bcachefs-tools from upstream
  # bcachefs-tools = upstreamPkgs.bcachefs-tools;

  # # Also use dracut from upstream to ensure it can handle the new kernel
  # dracut = upstreamPkgs.dracut;

  # # Add kmod from upstream to provide a compatible modprobe
  # kmod = upstreamPkgs.kmod;

  # # Add util-linux from upstream
  # util-linux = upstreamPkgs.util-linux;
}
