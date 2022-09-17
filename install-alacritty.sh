#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

mkdir -p ~/.config/

ln -sf $SCRIPT_DIR/.alacritty.yml ~/.alacritty.yml
sudo apt-get install -y xclip cmake pkg-config libfreetype6-dev libfontconfig1-dev libxcb-xfixes0-dev libxkbcommon-dev python3

git -C $SCRIPT_DIR submodule update --init --recursive
cargo build --release --manifest-path $SCRIPT_DIR/submodules/alacritty/Cargo.toml

sudo cp $SCRIPT_DIR/submodules/alacritty/target/release/alacritty /usr/local/bin # or anywhere else in $PATH
sudo cp $SCRIPT_DIR/submodules/alacritty/extra/logo/alacritty-term.svg /usr/share/pixmaps/Alacritty.svg
sudo desktop-file-install $SCRIPT_DIR/submodules/alacritty/extra/linux/Alacritty.desktop
sudo update-desktop-database