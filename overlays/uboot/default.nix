
{ channels, inputs, ... }:
(final: prev:
  let
    # Call unstable independently of the current pkgs
    unstablePkgs = import inputs.unstable {
      system = prev.system;
      config = prev.config; # inherit same config (optional)
    };
  in
  {
    inherit (unstablePkgs) buildUBoot ubootTools;

    # Replace all "uboot*" packages with their unstable equivalents
  } // builtins.listToAttrs (map
    (name: { name = name; value = unstablePkgs.${name}; })
    (builtins.filter (n: builtins.match "^uboot.*" n != null)
      (builtins.attrNames unstablePkgs)))
)
