{ channels, inputs, ... }:
self: super: {
  bambu-studio = super.appimageTools.wrapType2 rec {
    name = "BambuStudio";
    pname = "bambu-studio";
    version = "02.03.00.70";
    ubuntu_version = "24.04_PR-8184";
    
    src = super.fetchurl {
      url = "https://github.com/bambulab/BambuStudio/releases/download/v${version}/Bambu_Studio_ubuntu-${ubuntu_version}.AppImage";
      sha256 = "sha256:60ef861e204e7d6da518619bd7b7c5ab2ae2a1bd9a5fb79d10b7c4495f73b172";
    };

    profile = ''
      export SSL_CERT_FILE="${super.cacert}/etc/ssl/certs/ca-bundle.crt"
      export GIO_MODULE_DIR="${super.glib-networking}/lib/gio/modules/"
    '';
    
    extraPkgs = pkgs: with pkgs; [
      cacert
      glib
      glib-networking
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      webkitgtk_4_1
    ];

    desktopItems = [
      (super.makeDesktopItem {
        name = "bambu-studio";
        exec = "bambu-studio";
        icon = "bambu-studio"; # TODO: package the icon
        desktopName = "Bambu Studio";
        genericName = "3D Printer Slicer";
        categories = [ "3DGraphics" "Development" ];
      })
    ];
  };
}
# final: prev:
# let
#   # Import the pinned nixpkgs for this specific package
#   oldPkgs = import inputs.nixpkgs-bambu {
#     system = final.system;
#   };
# in
# {
#   # Use the old nixpkgs’ bambu-studio package directly
#   bambu-studio = oldPkgs.bambu-studio;
# }
