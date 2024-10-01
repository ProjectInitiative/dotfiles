#!/usr/bin/env bash

source_dir="."
dest_dir="/tmp/flattened"

mkdir -p "$dest_dir"

find "$source_dir" -type f -iname "*.nix" -print0 | while IFS= read -r -d '' file; do
    # Remove the source directory prefix
    relative_path="${file#$source_dir/}"
    # Replace / with _ in the path
    new_name=$(echo "$relative_path" | sed 's/\//_/g')
    # Copy the file with the new name
    cp "$file" "$dest_dir/$new_name"
done
