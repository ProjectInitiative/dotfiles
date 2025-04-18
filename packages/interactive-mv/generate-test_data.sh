#!/usr/bin/env bash

# Script to generate test directory structures for interactive-merge.sh

# --- Configuration ---
SRC_DIR="source_test"
DEST_DIR="destination_test"

# --- Cleanup previous run ---
echo "Cleaning up previous test directories..."
rm -rf "$SRC_DIR" "$DEST_DIR"
echo "Cleanup complete."
echo

# --- Create Source Directory Structure ---
echo "Creating source directory: $SRC_DIR"
mkdir -p "$SRC_DIR/subdir1"
mkdir -p "$SRC_DIR/subdir2/nested"
mkdir -p "$SRC_DIR/conflict_dir"
mkdir -p "$SRC_DIR/dir_vs_file_conflict"

echo "Creating source files..."
echo "Content from SOURCE unique_file.txt" > "$SRC_DIR/unique_file.txt"
echo "Content from SOURCE subdir1/file_a.txt" > "$SRC_DIR/subdir1/file_a.txt"
echo "Content from SOURCE subdir2/nested/deep_file.txt" > "$SRC_DIR/subdir2/nested/deep_file.txt"
echo "Content from SOURCE conflict_file.txt - WILL BE OVERWRITTEN?" > "$SRC_DIR/conflict_file.txt"
echo "Content from SOURCE conflict_dir/source_only_in_conflict_dir.txt" > "$SRC_DIR/conflict_dir/source_only_in_conflict_dir.txt"
echo "Content from SOURCE file_vs_dir_conflict.txt - Source is FILE" > "$SRC_DIR/file_vs_dir_conflict.txt"
echo "Content from SOURCE dir_vs_file_conflict/file_inside_dir.txt" > "$SRC_DIR/dir_vs_file_conflict/file_inside_dir.txt"
echo "Source empty file" > "$SRC_DIR/empty_source.txt"
touch "$SRC_DIR/empty_source.txt" # Ensure it's empty

echo "Source directory structure created."
echo

# --- Create Destination Directory Structure ---
echo "Creating destination directory: $DEST_DIR"
mkdir -p "$DEST_DIR/subdir1"
mkdir -p "$DEST_DIR/subdir3_dest_only"
mkdir -p "$DEST_DIR/conflict_dir"
mkdir -p "$DEST_DIR/file_vs_dir_conflict" # Dest is DIR

echo "Creating destination files..."
echo "Content from DESTINATION unique_dest_file.txt" > "$DEST_DIR/unique_dest_file.txt"
echo "Content from DESTINATION subdir1/file_b.txt" > "$DEST_DIR/subdir1/file_b.txt" # Different file in shared subdir
echo "Content from DESTINATION subdir3_dest_only/dest_file.txt" > "$DEST_DIR/subdir3_dest_only/dest_file.txt"
echo "Content from DESTINATION conflict_file.txt - ORIGINAL CONTENT" > "$DEST_DIR/conflict_file.txt" # File conflict
echo "Content from DESTINATION conflict_dir/dest_only_in_conflict_dir.txt" > "$DEST_DIR/conflict_dir/dest_only_in_conflict_dir.txt" # Dir conflict - different content
echo "Content from DESTINATION file_vs_dir_conflict/file_inside_dir.txt" > "$DEST_DIR/file_vs_dir_conflict/file_inside_dir.txt" # File vs Dir conflict
echo "Content from DESTINATION dir_vs_file_conflict.txt - Dest is FILE" > "$DEST_DIR/dir_vs_file_conflict.txt" # Dir vs File conflict
echo "Destination empty file" > "$DEST_DIR/empty_dest.txt"
touch "$DEST_DIR/empty_dest.txt" # Ensure it's empty

echo "Destination directory structure created."
echo

echo "Test data generation complete."
echo "Source: $SRC_DIR"
echo "Destination: $DEST_DIR"
