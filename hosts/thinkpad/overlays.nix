# nix-prefetch-git                                                                  │
# nix-prefetch-url --unpack https://github.com/realthunder/FreeCAD/archive/master.tar.gz
# nix-prefetch-github realthunder FreeCAD --rev LinkStable --nix

final: prev: {
  # freecad = prev.freecad.overrideAttrs (oldAttrs: {
  #   version = "0.22.0";
  #   src = prev.fetchFromGitHub {
  #     owner = "FreeCAD";
  #     repo = "FreeCAD";
  #     rev = "7ed1e9380acccd686a0e3573f883ac793aec3299";
  #     hash = "sha256-1NWCSohf2j+1ha6OlmVdqqMAiUXaCOX3PJ1xF3XR1BM=";
  #   };
  # });

  # Other overlay definitions...
  bambu-studio = prev.bambu-studio.overrideAttrs (oldAttrs: {
    version = "1.9.5";
    src = prev.fetchFromGitHub {
      owner = "bambulab";
      repo = "BambuStudio";
      rev = "22885b057ff5dfb6d65f57fb0c426655e349a2ba";
      hash = "sha256-m60/xZv8TGtdApOkGy1l5WQXcCf1eRB/bebQT2+v/64=";
    };
  });
  # Additional overrides as needed

}
