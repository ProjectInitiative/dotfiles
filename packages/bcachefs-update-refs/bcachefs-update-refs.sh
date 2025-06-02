#!/usr/bin/env bash
set -euo pipefail # Exit on error, undefined variable, or pipe failure

# --- Configuration ---
# Adjust these paths if your files are located elsewhere or named differently.
KERNEL_MODULE_FILE="$HOME/dotfiles/modules/nixos/system/bcachefs-kernel/default.nix"
TOOLS_OVERLAY_FILE="$HOME/dotfiles/overlays/bcachefs-tools/default.nix"

# Variable names to target in the Nix files
# Assuming both files use "defaultRev" and "defaultHash"
TARGET_REV_VAR_NAME="defaultRev"
TARGET_HASH_VAR_NAME="defaultHash"

update_nix_variable() {
  local file_path="$1"
  local var_name="$2"
  local new_value="$3"
  local value_regex_pattern="$4" # Regex to match the old value part

  if [ ! -f "$file_path" ]; then
    echo "Error: File not found: $file_path"
    exit 1
  fi

  echo "Attempting to update $var_name in $file_path to $new_value"

  echo "--- Lines containing '$var_name' in '$file_path' BEFORE sed ---"
  grep --color=never "$var_name" "$file_path" || echo "No lines containing '$var_name' found before sed."
  echo "----------------------------------------------------------------"

  # sed script:
  # Group 1: (\s*${var_name}\s*=\s*\")  - Matches '  defaultRev = "'
  # Group 2: (${value_regex_pattern})   - Matches the old value inside the quotes
  # Group 3: (\";\s*#.*)?               - Matches the closing quote, mandatory semicolon, and then an OPTIONAL comment
  # If no comment: (\";)?                - Matches closing quote and mandatory semicolon
  # Combined and robust: (\")(\s*;\s*#.*)? - More explicit capture: Group 2 is value, Group 3 is closing quote, Group 4 is optional semicolon+comment

  # Simpler and more direct for the given format:
  # (\s*${var_name}\s*=\s*\") : Matches up to and including the opening quote.
  # (${value_regex_pattern})  : Matches the value.
  # (\";.*)                   : Matches the closing quote, semicolon, and ANYTHING after (comment or nothing).
  # This should be robust enough for your line format.
  local sed_script="s|^(\s*${var_name}\s*=\s*\")(${value_regex_pattern})(\";.*)$|\1${new_value}\3|"
  local temp_file
  temp_file=$(mktemp)

  if sed -E "$sed_script" "$file_path" > "$temp_file"; then
    if cmp -s "$file_path" "$temp_file"; then
      echo "INFO: sed pattern for '$var_name' did not match any line in '$file_path'. No changes made by sed."
      echo "  sed pattern used: $sed_script"
      rm "$temp_file"
    else
      echo "INFO: sed pattern for '$var_name' matched and made changes. Replacing original file."
      mv "$temp_file" "$file_path"
    fi
  else
    echo "Error: sed command failed to execute for $var_name on $file_path."
    rm "$temp_file"
    exit 1
  fi

  if ! grep -qP "^\s*${var_name}\s*=\s*\"${new_value}\";" "$file_path"; then # Adjusted grep to expect semicolon
    echo "Error: Failed to update $var_name in $file_path to \"$new_value\"."
    echo "  Expected line (grep -P): ^\s*${var_name}\s*=\s*\"${new_value}\";"
    echo "  Please check the file format, sed pattern, and grep check."
    exit 1
  fi
  echo "$var_name in $file_path updated successfully."
}

# --- Main Logic ---

echo "Fetching latest bcachefs (kernel)..."
KERNEL_JSON=$(nix-prefetch-github --json --no-deep-clone koverstreet bcachefs --rev master)
KERNEL_REV=$(echo "$KERNEL_JSON" | jq -r '.rev')
KERNEL_HASH=$(echo "$KERNEL_JSON" | jq -r '.hash')

if [ -z "$KERNEL_REV" ] || [ "$KERNEL_REV" == "null" ] || [ -z "$KERNEL_HASH" ] || [ "$KERNEL_HASH" == "null" ]; then
  echo "Error: Failed to fetch rev or hash for bcachefs kernel."
  echo "JSON Output: $KERNEL_JSON"
  exit 1
fi
echo "  Kernel Rev: $KERNEL_REV"
echo "  Kernel Hash: $KERNEL_HASH"

update_nix_variable "$KERNEL_MODULE_FILE" "$TARGET_REV_VAR_NAME" "$KERNEL_REV" "[a-zA-Z0-9._/-]{7,}"
update_nix_variable "$KERNEL_MODULE_FILE" "$TARGET_HASH_VAR_NAME" "$KERNEL_HASH" "sha256-[a-zA-Z0-9+/=]{44}"

echo ""
echo "Fetching latest bcachefs-tools..."
TOOLS_JSON=$(nix-prefetch-github --json --no-deep-clone koverstreet bcachefs-tools --rev master)
TOOLS_REV=$(echo "$TOOLS_JSON" | jq -r '.rev')
TOOLS_HASH=$(echo "$TOOLS_JSON" | jq -r '.hash')

if [ -z "$TOOLS_REV" ] || [ "$TOOLS_REV" == "null" ] || [ -z "$TOOLS_HASH" ] || [ "$TOOLS_HASH" == "null" ]; then
  echo "Error: Failed to fetch rev or hash for bcachefs-tools."
  echo "JSON Output: $TOOLS_JSON"
  exit 1
fi
echo "  Tools Rev: $TOOLS_REV"
echo "  Tools Hash: $TOOLS_HASH"

update_nix_variable "$TOOLS_OVERLAY_FILE" "$TARGET_REV_VAR_NAME" "$TOOLS_REV" "[a-zA-Z0-9._/-]{7,}"
update_nix_variable "$TOOLS_OVERLAY_FILE" "$TARGET_HASH_VAR_NAME" "$TOOLS_HASH" "sha256-[a-zA-Z0-9+/=]{44}"

echo ""
echo "Update process complete."
echo "Please review the changes in the following files before committing:"
echo "  - $KERNEL_MODULE_FILE"
echo "  - $TOOLS_OVERLAY_FILE"
echo "Ensure your Nix files use '$TARGET_REV_VAR_NAME'/'$TARGET_HASH_VAR_NAME' correctly."
echo "You might need to rebuild your NixOS configuration for changes to take effect."

