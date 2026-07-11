#!/usr/bin/env bash
# pi-dev — rapid extension development workflow
#
# Copies extensions from Nix source to writable path for /reload iteration.
# Run this first, edit the source file, then /reload in pi to see changes.
# When stable, run `nh os switch` to lock it in via Nix.
#
# Usage:
#   pi-dev <name>          Copy extension to writable path (ready for /reload)
#   pi-dev <name> --edit   Copy then open in \$EDITOR
#   pi-dev <name> --watch  Watch source, auto-copy on save
#   pi-dev --list          Show available extensions

set -euo pipefail

EXTENSIONS_DIR="${PI_DEV_EXTENSIONS_DIR:-$HOME/dotfiles/modules/home/cli-apps/pi-coding-agent/extensions}"
AGENT_DIR="$HOME/.pi/agent/extensions"

function list_extensions() {
	echo "Available extensions:"
	if [ ! -d "$EXTENSIONS_DIR" ]; then
		echo "  (no extensions directory found at $EXTENSIONS_DIR)"
		echo "  Set PI_DEV_EXTENSIONS_DIR or run from your dotfiles repo."
		exit 0
	fi
	for f in "$EXTENSIONS_DIR"/*.ts; do
		[ -f "$f" ] || continue
		name="$(basename "$f" .ts)"
		status=""
		if [ -L "$AGENT_DIR/$name.ts" ]; then
			status=" (Nix-managed)"
		elif [ -f "$AGENT_DIR/$name.ts" ]; then
			status=" (local)"
		fi
		echo "  $name$status"
	done
}

function deploy_extension() {
	local name="$1"
	local src="$EXTENSIONS_DIR/$name.ts"
	local dst="$AGENT_DIR/$name.ts"

	if [ ! -f "$src" ]; then
		echo "Error: extension '$name' not found at $src" >&2
		return 1
	fi

	# Remove Nix-managed symlink if present, replace with writable copy
	if [ -L "$dst" ]; then
		rm "$dst"
	fi
	cp "$src" "$dst"
	echo "✓ Deployed $name.ts — run /reload in pi"
}

# --- Main ---

if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
	echo "pi-dev — rapid extension development for pi-coding-agent"
	echo ""
	echo "Usage:"
	echo "  pi-dev <name>          Copy extension to writable path"
	echo "  pi-dev <name> --edit   Copy then open in \$EDITOR"
	echo "  pi-dev <name> --watch  Watch source, auto-copy on change"
	echo "  pi-dev --list          Show available extensions"
	echo ""
	echo "Environment:"
	echo "  PI_DEV_EXTENSIONS_DIR  Override source directory"
	echo ""
	echo "Examples:"
	echo "  pi-dev dashboard-footer"
	echo "  pi-dev permissions --edit"
	echo "  pi-dev peek --watch"
	exit 0
fi

if [ "$1" = "--list" ]; then
	list_extensions
	exit 0
fi

name="$1"
shift

deploy_extension "$name" || exit 1

if [ "$1" = "--edit" ]; then
	${EDITOR:-vim} "$EXTENSIONS_DIR/$name.ts"
elif [ "$1" = "--watch" ]; then
	if ! command -v inotifywait &>/dev/null; then
		echo "Warning: inotifywait not found. Install inotify-tools or use a file watcher."
		echo "Falling back: just edit $EXTENSIONS_DIR/$name.ts and re-run pi-dev $name"
		exit 0
	fi
	echo "Watching $EXTENSIONS_DIR/$name.ts for changes..."
	echo "Run /reload in pi after each save."
	while inotifywait -q -e close_write "$EXTENSIONS_DIR/$name.ts"; do
		deploy_extension "$name"
	done
fi
