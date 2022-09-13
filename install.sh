#!/usr/bin/env bash

\mkdir -p "$HOME/.functions"

DEVENV=.functions/devenv

\touch "$HOME/.bashrc" && \grep -qF '$DEVENV' "$HOME/.bashrc" || printf "\nif [[ -f $HOME/$DEVENV ]]; then\n    source $HOME/$DEVENV\nfi\n" >> "$HOME/.bashrc"

cat << EOF | base64 --decode > $HOME/$DEVENV
CmZ1bmN0aW9uIGRldmVudigpIHsKICAgIAogIH0K
EOF
=======
apt-get update -qq && apt-get upgrade -qq -y > /dev/null && apt-get install -qq -y apt-utils > /dev/null

# install base dependencies
apt-get install -qq -y init systemd sudo curl ca-certificates git fuse > /dev/null

# install dev essentials
apt-get install -qq -y build-essential pkg-config openssl libssl-dev procps > /dev/null

# add apt keys
# google
curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
# helm
curl -fsSL https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
# update apt cache
apt-get update

# install tmux
apt install -qq -y tmux > /dev/null

# install neovim
#  curl --proto '=https' --tlsv1.2 -sSfL https://github.com/neovim/neovim/releases/download/v0.7.2/nvim.appimage -o /usr/local/bin/nvim && chmod +x /usr/local/bin/nvim
#  curl --proto '=https' --tlsv1.2 -sSfL https://github.com/neovim/neovim/releases/download/v0.7.2/nvim-linux64.tar.gz | tar -C /usr/local/bin -xz && chmod +x /usr/local/bin/nvim
curl --proto '=https' --tlsv1.2 -sSfL https://github.com/neovim/neovim/releases/download/v0.7.2/nvim-linux64.deb -o /tmp/nvim.deb && apt-get install -qq -y /tmp/nvim.deb > /dev/null


# install go
curl --proto '=https' --tlsv1.2 -sSfL https://go.dev/dl/go1.19.linux-amd64.tar.gz | tar -C /usr/local -xz

# install python
apt-get install -qq -y python3 python3-pip > /dev/null

# install kubernetes
apt-get install -y -qq kubectl helm > /dev/null
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null


