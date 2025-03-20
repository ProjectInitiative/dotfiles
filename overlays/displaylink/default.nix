{ channels, inputs, ... }:
final: prev: {
  displaylink =
    (prev.displaylink.override {
      requireFile =
        _:
        prev.fetchurl {
          url = "https://www.synaptics.com/sites/default/files/exe_files/2024-10/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.1-EXE.zip";
          name = "displaylink-610.zip";
          sha256 = "RJgVrX+Y8Nvz106Xh+W9N9uRLC2VO00fBJeS8vs7fKw=";
        };
    }).overrideAttrs
      (oldAttrs: {
        version = "6.1.0-17"; # Match the .run file's version in the ZIP
      });
}
