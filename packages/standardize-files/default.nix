{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
  # You also have access to your flake's inputs.
  inputs,

  # The namespace used for your flake, defaulting to "internal" if not set.
  namespace ? "internal",

  # All other arguments come from NixPkgs. You can use `pkgs` to pull packages or helpers
  # programmatically or you may add the named attributes as arguments here.
  pkgs,
  stdenv,
  writeShellApplication,
  coreutils, # Provides: echo, mkdir, cp, realpath, basename, mv
  findutils, # Provides: find
  ...
}:

let
  # The shell application that duplicates a directory and appends '.txt' to all files
  standardize-files = writeShellApplication {
    name = "standardize-files";
    runtimeInputs = [
      coreutils
      findutils
    ];
    # The shell script text.
    # Note the ''$ and ''${...} escaping for shell variables to prevent Nix interpolation.
    text = ''
      #!/usr/bin/env bash
      # Exit immediately if a command exits with a non-zero status.
      set -e

      print_usage() {
        # Escape $0 within $() using ''$0
        echo "Usage: $(basename "''$0") <source_directory> <destination_directory>" >&2
        echo "Duplicates a directory, including hidden files, and appends '.txt' to all copied files." >&2
      }

      # Check for the correct number of arguments ($#) using ''$#
      if [ "''$#" -ne 2 ]; then
        echo "Error: Incorrect number of arguments." >&2
        print_usage
        exit 1
      fi

      # Assign positional arguments ($1, $2) using ''$1, ''$2
      source_dir="''$1"
      dest_dir="''$2"

      # Validate source directory exists using ''$source_dir
      if [ ! -d "''$source_dir" ]; then
        echo "Error: Source directory ' ''$source_dir' does not exist or is not a directory." >&2
        exit 1
      fi

      # Resolve absolute paths for comparison using ''$source_dir, ''$dest_dir
      # Need to escape ''$dest_dir twice for the || echo part
      resolved_source=$(realpath "''$source_dir")
      resolved_dest=$(realpath "''$dest_dir" 2>/dev/null || echo "''$dest_dir")

      # Prevent source and destination being the same using ''$resolved_source, ''$resolved_dest
      if [ "''$resolved_source" = "''$resolved_dest" ]; then
        echo "Error: Source and destination directories cannot be the same." >&2
        exit 1
      fi

      # Create destination directory if it doesn't exist using ''$dest_dir
      echo "Ensuring destination directory exists: ' ''$dest_dir'"
      mkdir -p "''$dest_dir"

      # Copy directory structure using ''$source_dir, ''$dest_dir
      echo "Copying directory structure from ' ''$source_dir' to ' ''$dest_dir'..."
      # Use subshell ( ) and cd to handle relative paths correctly, including hidden files (cp -a .)
      (cd "''$source_dir" && cp -a . "''$dest_dir/")
      echo "Initial copy complete."

      # Find all files in the destination directory and rename them using find -exec
      echo "Appending '.txt' to all files in ' ''$dest_dir'..."
      # Use ''$dest_dir in find command.
      # Use -exec to run mv directly. {} is replaced by find with the filename.
      # Use -- with mv to handle filenames starting with '-'.
      # The \; terminates the -exec command.
      find "''$dest_dir" -depth -type f -exec mv -- {} {}.txt \;

      # Print final confirmation using ''$resolved_source, ''$resolved_dest
      echo "Directory duplication and renaming complete."
      echo "Source: ' ''$resolved_source'"
      echo "Destination: ' ''$resolved_dest'"

      # Exit successfully
      exit 0
    ''; # End of text block
  }; # End of writeShellApplication arguments
in # Start of the final expression part of the let block
# The result of the expression is the derivation
standardize-files
