{ channels, inputs, ... }:
final: prev: {
  # Update the evdi in kernelPackages
  # linuxPackages = prev.linuxPackages.extend (
  #   kself: ksuper: {
  #     evdi = channels.unstable.linuxPackages.evdi.override {
  #       kernel = kself.kernel;
  #     };
  #   }
  # );

  # # Do the same for your specific kernel if you're not using the default
  # linuxPackages_latest = prev.linuxPackages_latest.extend (
  #   kself: ksuper: {
  #     evdi = channels.unstable.linuxPackages_latest.evdi.override {
  #       kernel = kself.kernel;
  #     };
  #   }
  # );
  # linuxPackages_6_14 = prev.linuxPackages_6_14.extend (
  #   kself: ksuper: {
  #     evdi = channels.unstable.linuxPackages_6_14.evdi.override {
  #       kernel = kself.kernel;
  #     };
  #   }
  # );
  # inherit (channels.unstable) linuxPackages;
  displaylink =
    (prev.displaylink.override {
      requireFile =
        _:
        prev.fetchurl {
          url = "https://www.synaptics.com/sites/default/files/exe_files/2025-04/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.1.1-EXE.zip";
          name = "displaylink-611.zip";
          sha256 = "sha256-yiIw6UDOLV1LujxhAVsfjIA5he++8W022+EK/OZTwXI=";
          # url = "https://www.synaptics.com/sites/default/files/exe_files/2024-10/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.1-EXE.zip";
          # name = "displaylink-610.zip";
          # sha256 = "RJgVrX+Y8Nvz106Xh+W9N9uRLC2VO00fBJeS8vs7fKw=";
        };
    }).overrideAttrs

      (
        oldAttrs: {
          __intentionallyOverridingVersion = true;
          version = "6.1.1-17"; # Match the .run file's version in the ZIP
        }
      );
}
