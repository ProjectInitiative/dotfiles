#!/usr/bin/env bash

\mkdir -p "$HOME/.functions"

DEVENV=.functions/devenv

\touch "$HOME/.bashrc" && \grep -qF '$DEVENV' "$HOME/.bashrc" || printf "\nif [[ -f $HOME/$DEVENV ]]; then\n    source $HOME/$DEVENV\nfi\n" >> "$HOME/.bashrc"

cat << EOF | base64 --decode > $HOME/$DEVENV
CmZ1bmN0aW9uIGRldmVudigpIHsKICAgIAogIH0K
EOF
