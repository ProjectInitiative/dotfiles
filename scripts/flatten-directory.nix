#nix run .#flattenDirectory -- . /tmp/flattened --nix-only --skip-git
{ lib, writeShellApplication, coreutils, findutils, gnused }:

writeShellApplication {
  name = "flatten-directory";
  runtimeInputs = [ coreutils findutils gnused ];
  text = ''
    print_usage() {
      echo "Usage: $0 <source_directory> <destination_directory> [options]"
      echo "Options:"
      echo "  --nix-only    Only include .nix files"
      echo "  --skip-git    Skip .git directory"
    }

    if [ $# -lt 2 ]; then
      print_usage
      exit 1
    fi

    source_dir="$1"
    dest_dir="$2"
    shift 2

    nix_only=false
    skip_git=false

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --nix-only) nix_only=true ;;
        --skip-git) skip_git=true ;;
        *) echo "Unknown option: $1"; print_usage; exit 1 ;;
      esac
      shift
    done

    if [ ! -d "$source_dir" ]; then
      echo "Source directory does not exist: $source_dir"
      exit 1
    fi

    mkdir -p "$dest_dir"

    find_args=("$source_dir" -type f)
    if [ "$nix_only" = true ]; then
      find_args+=(-name "*.nix")
    fi
    if [ "$skip_git" = true ]; then
      find_args+=(-not -path "*.git*")
    fi

    while IFS= read -r -d "" file; do
      relative_path="''${file#"$source_dir"/}"
      new_name=$(echo "$relative_path" | sed 's/\//_/g')
      cp "$file" "$dest_dir/$new_name"
    done < <(find "''${find_args[@]}" -print0)

    echo "Directory flattened successfully."
  '';
}
