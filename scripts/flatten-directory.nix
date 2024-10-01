{ lib, writeShellApplication, coreutils, findutils, gnused }:

writeShellApplication {
  name = "flatten-directory";
  runtimeInputs = [ coreutils findutils gnused ];
  text = ''
    print_usage() {
      echo "Usage: $0 <source_directory> <destination_directory> [options]"
      echo "Options:"
      echo "  --extensions <ext1,ext2,...>  Only include files with specified extensions"
      echo "  --skip-git                    Skip .git directory"
    }

    if [ $# -lt 2 ]; then
      print_usage
      exit 1
    fi

    source_dir="$1"
    dest_dir="$2"
    shift 2

    extensions=""
    skip_git=false

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --extensions)
          if [ -n "$2" ] && [ "$(echo "$2" | cut -c1-1)" != "-" ]; then
            extensions=$2
            shift
          else
            echo "Error: --extensions requires a comma-separated list of extensions"
            exit 1
          fi
          ;;
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
    if [ -n "$extensions" ]; then
      IFS=',' read -ra ext_array <<< "$extensions"
      find_args+=( '(' )
      for ext in "''${ext_array[@]}"; do
        find_args+=( -name "*.$ext" -o )
      done
      unset 'find_args[''${#find_args[@]}-1]'  # Remove last '-o'
      find_args+=( ')' )
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
