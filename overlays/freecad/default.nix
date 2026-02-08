{ channels, inputs, ... }:

final: prev: {
  freecad = prev.freecad.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.wrapGAppsHook3 ];
  });
}