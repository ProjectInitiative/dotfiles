#!/bin/bash

export PATH="$PATH:/home/linuxbrew/.linuxbrew/bin"
# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -f|--file)
            BREWFILE="$2"
            shift
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set default Brewfile location if not provided
if [ -z "$BREWFILE" ]; then
    BREWFILE="$HOME/Brewfile"
fi

# Update Homebrew and upgrade any installed packages
brew update
brew upgrade

# Install all packages listed in the Brewfile
brew bundle install --file="$BREWFILE"

# Clean up any old versions of packages that are no longer needed
brew cleanup

