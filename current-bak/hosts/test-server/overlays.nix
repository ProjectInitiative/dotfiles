final: prev: {
  freecad = prev.freecad.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      (final.fetchpatch {
        url = "https://github.com/NixOS/nixpkgs/pull/344005.patch";
        sha256 = "sha256-0qvk9s6zfxx1sgddp7ji1fwbv2qw3isyllbzk7h96vnqxsb1ikxj";
      })
    ];
  });
}
