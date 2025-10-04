{ inputs, ... }: final: prev:
let
  unstablePkgs = import inputs.unstable {
    system = prev.system;
    config.allowUnfree = true;
  };
in
{
  linuxPackagesFor = kernel:
    let
      linuxPackages = prev.linuxPackagesFor kernel;
    in
      linuxPackages.overrideScope (lfinal: lprev: {
        kernel = lprev.kernel.overrideAttrs (old: {
          extraPackages = (old.extraPackages or []) ++ [ unstablePkgs.bcachefs-tools ];
        });
      });
}