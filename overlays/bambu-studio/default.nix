# { channels, inputs, ... }:
# self: super: {
#   bambu-studio = super.appimageTools.wrapType2 rec {
#     name = "BambuStudio";
#     pname = "bambu-studio";
#     version = "02.03.00.70";
#     ubuntu_version = "24.04_PR-8184";
    
#     src = super.fetchurl {
#       url = "https://github.com/bambulab/BambuStudio/releases/download/v${version}/Bambu_Studio_ubuntu-${ubuntu_version}.AppImage";
#       sha256 = "sha256:60ef861e204e7d6da518619bd7b7c5ab2ae2a1bd9a5fb79d10b7c4495f73b172";
#     };

#     profile = ''
#       export SSL_CERT_FILE="${super.cacert}/etc/ssl/certs/ca-bundle.crt"
#       export GIO_MODULE_DIR="${super.glib-networking}/lib/gio/modules/"
#     '';
    
#     extraPkgs = pkgs: with pkgs; [
#       cacert
#       glib
#       glib-networking
#       gst_all_1.gst-plugins-bad
#       gst_all_1.gst-plugins-base
#       gst_all_1.gst-plugins-good
#       webkitgtk_4_1
#     ];

#     extraInstallCommands = ''
#       # Extract the AppImage
#       cp ${src} ./bambu.AppImage
#       chmod +x ./bambu.AppImage
#       ./bambu.AppImage --appimage-extract
#       install -Dm644 squashfs-root/BambuStudio.png $out/share/icons/hicolor/512x512/apps/bambu-studio.png
#       rm -rf squashfs-root ./bambu.AppImage
#     '';

#     desktopItems = [
#       (super.makeDesktopItem {
#         name = "bambu-studio";
#         exec = "bambu-studio";
#         icon = "bambu-studio";
#         desktopName = "Bambu Studio";
#         genericName = "3D Printer Slicer";
#         categories = [ "3DGraphics" "Development" ];
#       })
#     ];
#   };
# }
# # final: prev:
# # let
# #   # Import the pinned nixpkgs for this specific package
# #   oldPkgs = import inputs.nixpkgs-bambu {
# #     system = final.system;
# #   };
# # in
# # {
# #   # Use the old nixpkgs’ bambu-studio package directly
# #   bambu-studio = oldPkgs.bambu-studio;
# # }

{ channels, inputs, ... }:
self: super: {
  bambu-studio = super.appimageTools.wrapType2 rec {
    name = "BambuStudio";
    pname = "bambu-studio";
    version = "02.04.00.70";
    ubuntu_version = "24.04_PR-8834";
    
    src = super.fetchurl {
      url = "https://github.com/bambulab/BambuStudio/releases/download/v${version}/Bambu_Studio_ubuntu-${ubuntu_version}.AppImage";
      sha256 = "sha256-JrwH3MsE3y5GKx4Do3ZlCSAcRuJzEqFYRPb11/3x3r0=";
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

    extraInstallCommands = ''
      # Extract the AppImage
      cp ${src} ./bambu.AppImage
      chmod +x ./bambu.AppImage
      ./bambu.AppImage --appimage-extract

      # Icon
      install -Dm644 squashfs-root/BambuStudio.png \
        $out/share/icons/hicolor/512x512/apps/bambu-studio.png

      # Patch Exec line inside the .desktop file
      substituteInPlace squashfs-root/BambuStudio.desktop \
        --replace "Exec=AppRun" "Exec=${pname}"

      # Install .desktop file so desktops can see it
      install -Dm644 squashfs-root/BambuStudio.desktop \
        $out/share/applications/bambu-studio.desktop

      # Cleanup
      rm -rf squashfs-root ./bambu.AppImage
    '';
  };
}
