#!/usr/bin/env bash

# script_dir=$( cd -- "$( dirname -- "${bash_source[0]}" )" &> /dev/null && pwd )

# mkdir -p ~/.config/
# cargo install cargo-make

git -C $SCRIPT_DIR submodule update --init --recursive
git -C $SCRIPT_DIR submodule update --remote --merge
cargo install --path $SCRIPT_DIR/submodules/zellij
