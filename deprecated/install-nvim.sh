#!/usr/bin/env bash

VERSION="v0.7.2"

cd $HOME

mkdir -p $HOME/.config/nvim/

curl -OL "https://github.com/neovim/neovim/releases/download/$VERSION/nvim.appimage"

chmod +x $HOME/nvim.appimage
sudo mv $HOME/nvim.appimage /usr/bin/nvim


# install packer
git clone --depth 1 https://github.com/wbthomason/packer.nvim $HOME/.local/share/nvim/site/pack/packer/start/packer.nvim
