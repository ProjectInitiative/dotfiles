{ inputs, ... }:
final: prev:
let
  upstreamPkgs = import inputs.upstream {
    system = prev.system;
  };
in {
  # Override kernelPackages to use upstream
  linuxPackages_latest = upstreamPkgs.linuxPackages_latest;
  linuxPackages_6_16   = upstreamPkgs.linuxPackages_6_16;

  # Use bcachefs-tools from upstream
  bcachefs-tools = upstreamPkgs.bcachefs-tools;

}
