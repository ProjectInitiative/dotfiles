#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

mkdir -p ~/.config/
rm -rf ~/.config/helix
ln -s $SCRIPT_DIR/helix/ ~/.config/

git -C $SCRIPT_DIR submodule update --init --recursive

cargo install --path $SCRIPT_DIR/submodules/helix/helix-term

mkdir -p $SCRIPT_DIR/helix/runtime
cp -fr $SCRIPT_DIR/submodules/helix/runtime/* $SCRIPT_DIR/helix/runtime/
