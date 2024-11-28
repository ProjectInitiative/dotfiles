#!/usr/bin/env zsh

set -e

USER_HOME="/home/kylepzak"
APPIMAGE_DIR="$USER_HOME/.local/bin"
DESKTOP_DIR="$USER_HOME/.local/share/applications"

mkdir -p "$APPIMAGE_DIR"
mkdir -p "$DESKTOP_DIR"

download_appimage() {
    local name="$1"
    local url="$2"
    local target_dir="$APPIMAGE_DIR/$name"
    local target_file="$target_dir/$name.AppImage"

    mkdir -p "$target_dir"

    if [ ! -f "$target_file" ]; then
        echo "Downloading $name AppImage..."
        curl -L "$url" -o "$target_file"
        chmod +x "$target_file"
    else
        echo "$name AppImage already exists, skipping download."
    fi

    create_desktop_entry "$name" "$target_file"
}

create_desktop_entry() {
    local name="$1"
    local exec_path="$2"
    local desktop_file="$DESKTOP_DIR/$name.desktop"

    cat > "$desktop_file" <<EOF
[Desktop Entry]
Name=$name
Exec=$exec_path
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
