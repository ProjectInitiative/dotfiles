{ inputs, ... }:
final: prev:
let
  unstablePkgs = import inputs.unstable {
    system = prev.system;
  };
in {
  # Override kernelPackages to use unstable
  linuxPackages_latest = unstablePkgs.linuxPackages_latest;
  # linuxPackages_6_16   = unstablePkgs.linuxPackages_6_16;

  # Use bcachefs-tools from unstable
  bcachefs-tools = unstablePkgs.bcachefs-tools;

  # Expose the bcachefs kernel module package from unstable
  bcachefs-kernel-module = unstablePkgs.bcachefs-kernel-module;
}
