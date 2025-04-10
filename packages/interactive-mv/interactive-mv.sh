#!/usr/bin/env bash

# --- Configuration ---
# Set to 1 to enable debug messages
DEBUG=0

# --- Functions ---
debug_log() {
  [ "$DEBUG" -eq 1 ] && echo "DEBUG: $1" >&2
}

usage() {
  echo "Usage: $0 <source_directory> <destination_directory>"
  echo "Merges contents of source_directory into destination_directory interactively."
  echo "Uses 'mv' for speed when possible (same filesystem)."
  exit 1
}

prompt_user() {
  local src_item="$1"
  local dest_item="$2"
  local choice=""

  # Describe the conflict
  local src_type="item"
  local dest_type="item"
  [ -f "$src_item" ] && src_type="file" || { [ -d "$src_item" ] && src_type="directory"; }
  [ -f "$dest_item" ] && dest_type="file" || { [ -d "$dest_item" ] && dest_type="directory"; }

  echo "Conflict detected for: ${src_item#$SRC_DIR/}"
  echo "  Source: $src_type ($src_item)"
  echo "  Destination: $dest_type ($dest_item)"

  while true; do
    # Prompt user - UPDATED OPTIONS TEXT AND DEFAULT
    read -p "Choose action: (o)verwrite, (s)kip, (O)verwrite all subsequent, (S)kip all subsequent, (q)uit? [s] " choice
    choice=${choice:-s} # Default to skip (lowercase s) if user just presses Enter

    # UPDATED CASE STATEMENT LOGIC
    case "$choice" in
      o) # Lowercase o: Overwrite single item
        echo "Overwrite"
        return 0 # Indicates Overwrite
        ;;
      s) # Lowercase s: Skip single item
        echo "Skip"
        return 1 # Indicates Skip
        ;;
      O) # Uppercase O: Overwrite All
        echo "Overwrite All"
        apply_to_all="overwrite"
        return 0 # Indicates Overwrite (for this one too)
        ;;
      S) # Uppercase S: Skip All
        echo "Skip All"
        apply_to_all="skip"
        return 1 # Indicates Skip (for this one too)
        ;;
      [Qq]) # Quit
        echo "Quitting."
        exit 2
        ;;
      *)
        echo "Invalid choice. Please try again."
        ;;
    esac
  done
}

# --- Main Script ---

# Check arguments
if [ "$#" -ne 2 ]; then
  usage
fi

SRC_DIR="$1"
DEST_DIR="$2"

# Validate directories
if [ ! -d "$SRC_DIR" ]; then
  echo "Error: Source directory '$SRC_DIR' not found or not a directory."
  exit 1
fi
if [ ! -d "$DEST_DIR" ]; then
  echo "Error: Destination directory '$DEST_DIR' not found or not a directory."
  exit 1
fi

# Canonicalize paths (resolve symlinks, remove trailing slashes)
SRC_DIR=$(readlink -f "$SRC_DIR")
DEST_DIR=$(readlink -f "$DEST_DIR")

# Prevent merging directory into itself
if [ "$SRC_DIR" = "$DEST_DIR" ]; then
    echo "Error: Source and destination directories are the same."
    exit 1
fi

# State variable for "Apply to All" choice
apply_to_all="" # Can be "", "overwrite", or "skip"

# Use find to traverse the source directory safely
find "$SRC_DIR" -mindepth 1 -print0 | while IFS= read -r -d $'\0' src_item; do
  # Calculate relative path within source directory
  relative_path="${src_item#$SRC_DIR/}"
  debug_log "Processing source item: $src_item (Relative: $relative_path)"

  # Construct corresponding path in destination directory
  dest_item="$DEST_DIR/$relative_path"
  debug_log "Potential destination path: $dest_item"

  # Ensure parent directory exists in destination *before* trying to move
  dest_parent_dir=$(dirname "$dest_item")
  if [ ! -d "$dest_parent_dir" ]; then
    debug_log "Creating destination parent directory: $dest_parent_dir"
    mkdir -p -- "$dest_parent_dir"
    if [ $? -ne 0 ]; then
      echo "Error: Failed to create directory '$dest_parent_dir'. Skipping '$src_item'."
      continue # Skip to next item
    fi
  fi

  # --- Conflict Resolution ---
  action_needed=true
  if [ -e "$dest_item" ] || [ -L "$dest_item" ]; then # Check if destination exists
    debug_log "Conflict detected: '$dest_item' exists."

    # Apply global choice if set
    if [ "$apply_to_all" = "overwrite" ]; then
      echo "Applying 'Overwrite All' to: $relative_path"
      user_choice=0 # 0 means Overwrite
    elif [ "$apply_to_all" = "skip" ]; then
       echo "Applying 'Skip All' to: $relative_path"
      user_choice=1 # 1 means Skip
    else
      # Prompt user otherwise
      prompt_user "$src_item" "$dest_item"
      user_choice=$? # Get return code from function (0=overwrite, 1=skip)
    fi

    # Perform action based on user choice
    if [ "$user_choice" -eq 0 ]; then
      # Overwrite
      rm -rf -- "$dest_item"
      if [ $? -ne 0 ] && [ -e "$dest_item" ]; then
          echo "Error: Could not remove existing destination '$dest_item'. Skipping."
          action_needed=false
      else
          debug_log "Removed existing destination '$dest_item' for overwrite."
          action_needed=true
      fi
    else
      # Skip
      debug_log "Skipping source item '$src_item'."
      action_needed=false
    fi
  else
    # No conflict
    debug_log "No conflict for '$dest_item'. Moving."
    action_needed=true
  fi

  # --- Perform Move (if action_needed) ---
  if $action_needed; then
    debug_log "Executing: mv -- '$src_item' '$dest_item'"
    mv -- "$src_item" "$dest_item"
    if [ $? -ne 0 ]; then
      echo "Error: Failed to move '$src_item' to '$dest_item'. It might be left in source." >&2
    else
       debug_log "Successfully moved '$src_item' to '$dest_item'."
    fi
  fi
  # Add a newline for better readability
  echo ""
done

echo "Merge process completed."
exit 0
