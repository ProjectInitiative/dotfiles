#!/usr/bin/env bash
# pi-dev — rapid extension development for pi-coding-agent
#
# Deploys extensions from Nix source to writable path for /reload testing.
# Supports one or multiple extensions at once.
#
# Usage:
#   pi-dev <name>...              Deploy one or more extensions
#   pi-dev --all                  Deploy ALL extensions
#   pi-dev --all --watch          Watch ALL source files, auto-deploy on change
#   pi-dev <name> --watch         Watch one extension
#   pi-dev <name> --edit          Deploy + open in $EDITOR
#   pi-dev --list                 Show available extensions
#
# Examples:
#   pi-dev dashboard-footer peek          # deploy both at once
#   pi-dev --all                           # deploy everything for testing
#   pi-dev --all --watch                   # watch all, auto-copy on save
#   pi-dev permissions --edit              # deploy + edit

set -euo pipefail

EXTENSIONS_DIR="${PI_DEV_EXTENSIONS_DIR:-$HOME/dotfiles/modules/home/cli-apps/pi-coding-agent/extensions}"
AGENT_DIR="$HOME/.pi/agent/extensions"

# ── Helpers ───────────────────────────────────────────────────────────────────

function list_extensions() {
	echo "Available extensions:" >&2
	if [ ! -d "$EXTENSIONS_DIR" ]; then
		echo "  (no extensions directory found at $EXTENSIONS_DIR)" >&2
		exit 1
	fi
	local count=0
	for f in "$EXTENSIONS_DIR"/*.ts; do
		[ -f "$f" ] || continue
		name="$(basename "$f" .ts)"
		status=""
		if [ -L "$AGENT_DIR/$name.ts" ]; then
			status=" (Nix-managed)"
		elif [ -f "$AGENT_DIR/$name.ts" ]; then
			status=" (local)"
		fi
		echo "  $name$status" >&2
		count=$((count + 1))
	done
	if [ "$count" -eq 0 ]; then
		echo "  (none found)" >&2
	fi
	# Print names on stdout for programmatic use
	for f in "$EXTENSIONS_DIR"/*.ts; do
		[ -f "$f" ] || continue
		basename "$f" .ts
	done
}

function deploy_extension() {
	local name="$1"
	local src="$EXTENSIONS_DIR/$name.ts"
	local dst="$AGENT_DIR/$name.ts"

	if [ ! -f "$src" ]; then
		echo "    ✗ $name.ts — source not found at $src" >&2
		return 1
	fi

	# Remove Nix-managed symlink if present, replace with writable copy
	if [ -L "$dst" ] || [ -f "$dst" ]; then
		rm -f "$dst"
	fi
	cp "$src" "$dst"
	echo "    ✓ $name.ts" >&2
}

function deploy_all() {
	echo "Deploying extensions:" >&2
	local ok=true
	for name in $(list_extensions); do
		deploy_extension "$name" || ok=false
	done
	$ok && echo "Done — run /reload in pi" >&2 || echo "Some extensions failed" >&2
}

# ── Watch helpers ─────────────────────────────────────────────────────────────

_watch_pid=""
_watch_extensions=""

function stop_watch() {
	if [ -n "$_watch_pid" ]; then
		kill "$_watch_pid" 2>/dev/null || true
		_watch_pid=""
	fi
}

function watch_loop() {
	local names=("$@")
	echo "Watching ${#names[@]} extension(s) for changes..." >&2
	echo "Run /reload in pi after each save." >&2
	echo "Press Ctrl+C to stop." >&2

	# Build inotifywait args for all source files
	local watch_files=()
	for name in "${names[@]}"; do
		watch_files+=("$EXTENSIONS_DIR/$name.ts")
	done

	# First deploy
	for name in "${names[@]}"; do
		deploy_extension "$name"
	done

	# Use inotifywait monitor mode — outputs filename on each change
	# The -m flag keeps watching, -q suppresses headers
	inotifywait -q -m -e close_write "${watch_files[@]}" --format '%f' \
	| while read -r changed_file; do
		if [ -n "$changed_file" ]; then
			local name="${changed_file%.ts}"
			deploy_extension "$name"
			echo "  → /reload ready" >&2
		fi
	done
}

# ── Main ──────────────────────────────────────────────────────────────────────

if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
	echo "pi-dev — rapid extension development for pi-coding-agent"
	echo ""
	echo "Usage:"
	echo "  pi-dev <name>...              Deploy one or more extensions"
	echo "  pi-dev --all                  Deploy ALL extensions"
	echo "  pi-dev --all --watch          Watch ALL source files"
	echo "  pi-dev <name> --watch         Watch one extension"
	echo "  pi-dev <name> --edit          Deploy + open in \$EDITOR"
	echo "  pi-dev --list                 Show available extensions"
	echo ""
	echo "Examples:"
	echo "  pi-dev dashboard-footer peek"
	echo "  pi-dev --all --watch"
	echo "  pi-dev permissions --edit"
	exit 0
fi

if [ "$1" = "--list" ]; then
	list_extensions >/dev/null
	exit 0
fi

WATCH_MODE=false
EDIT_MODE=false
NAMES=()

for arg in "$@"; do
	case "$arg" in
	--watch) WATCH_MODE=true ;;
	--edit) EDIT_MODE=true ;;
	--all) NAMES=("$(list_extensions)") ;;
	*) NAMES+=("$arg") ;;
	esac
done

if [ ${#NAMES[@]} -eq 0 ]; then
	echo "Error: no extensions specified. Use --all or provide names." >&2
	echo "Run 'pi-dev --list' to see available extensions." >&2
	exit 1
fi

# Deduplicate names
readarray -t NAMES < <(printf "%s\n" "${NAMES[@]}" | sort -u)

if $WATCH_MODE; then
	trap stop_watch EXIT
	watch_loop "${NAMES[@]}"
elif $EDIT_MODE; then
	echo "Deploying:" >&2
	for name in "${NAMES[@]}"; do
		deploy_extension "$name"
	done
	${EDITOR:-vim} "${NAMES[@]/#/$EXTENSIONS_DIR/}.ts"
else
	echo "Deploying:" >&2
	for name in "${NAMES[@]}"; do
		deploy_extension "$name"
	done
	echo "Done — run /reload in pi" >&2
fi
