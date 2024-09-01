{ config, pkgs, lib, ... }:

let
  appImageUrls = [
    {
      name = "MQTTExplorer";
      url = "https://github.com/thomasnordquist/MQTT-Explorer/releases/download/v0.4.0-beta.6/MQTT-Explorer-0.4.0-beta.6.AppImage";
    }
    {
      name = "FreeCADRealThunder";
      url = "https://github.com/realthunder/FreeCAD/releases/download/20240407stable/FreeCAD-Link-Stable-Linux-aarch64-py3.11-20240407.AppImage";
    }
    # Add more AppImages as needed
  ];

appImageScript = pkgs.writeScriptBin "manage-appimages" ''
    #!${pkgs.runtimeShell}

    set -e

    USER_HOME="/home/${config.users.users.kylepzak.name}"
    APPIMAGE_DIR="$USER_HOME/.local/bin"
    DESKTOP_DIR="$USER_HOME/.local/share/applications"

    ${pkgs.coreutils}/bin/mkdir -p "$APPIMAGE_DIR"
    ${pkgs.coreutils}/bin/mkdir -p "$DESKTOP_DIR"

    download_appimage() {
        local name="$1"
        local url="$2"
        local target_dir="$APPIMAGE_DIR/$name"
        local target_file="$target_dir/$name.AppImage"

        ${pkgs.coreutils}/bin/mkdir -p "$target_dir"

        if [ ! -f "$target_file" ]; then
            echo "Downloading $name AppImage..."
            ${pkgs.curl}/bin/curl -L "$url" -o "$target_file"
            ${pkgs.coreutils}/bin/chmod +x "$target_file"
        else
            echo "$name AppImage already exists, skipping download."
        fi

        create_desktop_entry "$name" "$target_file"
    }

    create_desktop_entry() {
        local name="$1"
        local exec_path="$2"
        local desktop_file="$DESKTOP_DIR/$name.desktop"

        ${pkgs.coreutils}/bin/cat > "$desktop_file" <<EOF
    [Desktop Entry]
    Name=$name
    Exec=${pkgs.appimage-run}/bin/appimage-run $exec_path
    Type=Application
    Categories=Utility;
    EOF

        echo "Created desktop entry for $name"
    }

    # Main script
    while [ "$#" -gt 0 ]; do
        download_appimage "$1" "$2"
        shift 2
    done

    echo "AppImage installation complete."
  '';

in {
  environment.systemPackages = [ appImageScript pkgs.appimage-run ]
    ++ (map (app: pkgs.writeScriptBin app.name ''
      #!/bin/sh
      ${pkgs.appimage-run}/bin/appimage-run /home/${config.users.users.kylepzak.name}/.local/bin/${app.name}/${app.name}.AppImage "$@"
    '') appImageUrls);

  system.activationScripts.downloadAppImages = ''
    ${appImageScript}/bin/manage-appimages ${lib.concatMapStringsSep " " (app: "${app.name} ${app.url}") appImageUrls}
  '';
}
