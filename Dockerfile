FROM docker.io/ubuntu:20.04

ENV DEBIAN_FRONTEND noninteractive
ARG TZ="America/Chicago"
SHELL ["/bin/bash", "-c"]

# Overide user name at build, if buil-arg no passed, will create user named `default` user
ENV USER=default_user

# Create a group and user
RUN useradd -m ${USER}   
# RUN useradd -m linuxbrew
# RUN chmod 0755 /home/linuxbrew
# # install homebrew
# USER linuxbrew
# RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# update apt cache and upgrade packages
RUN apt-get update -qq && apt-get upgrade -qq -y > /dev/null && apt-get install -qq -y apt-utils > /dev/null

# install base dependencies
RUN apt-get install -qq -y init systemd sudo curl ca-certificates git fuse > /dev/null

# install dev essentials
RUN apt-get install -qq -y build-essential pkg-config openssl libssl-dev procps > /dev/null

# add apt keys
# google
RUN curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
# helm
RUN curl -fsSL https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
# update apt cache
RUN apt-get update

# install tmux
RUN apt install -qq -y tmux > /dev/null

# install neovim
# RUN curl --proto '=https' --tlsv1.2 -sSfL https://github.com/neovim/neovim/releases/download/v0.7.2/nvim.appimage -o /usr/local/bin/nvim && chmod +x /usr/local/bin/nvim
# RUN curl --proto '=https' --tlsv1.2 -sSfL https://github.com/neovim/neovim/releases/download/v0.7.2/nvim-linux64.tar.gz | tar -C /usr/local/bin -xz && chmod +x /usr/local/bin/nvim
RUN curl --proto '=https' --tlsv1.2 -sSfL https://github.com/neovim/neovim/releases/download/v0.7.2/nvim-linux64.deb -o /tmp/nvim.deb && apt-get install -qq -y /tmp/nvim.deb > /dev/null


# install go
RUN curl --proto '=https' --tlsv1.2 -sSfL https://go.dev/dl/go1.19.linux-amd64.tar.gz | tar -C /usr/local -xz

# install python
RUN apt-get install -qq -y python3 python3-pip > /dev/null

# install kubernetes
RUN apt-get install -y -qq kubectl helm > /dev/null
RUN kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null


# local user installs
USER ${USER}
# COPY .bashrc and other configs
RUN echo 'PATH="$PATH:$HOME/.local/bin"' >> $HOME/.profile

# install rust
RUN sh <(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs) -q -y > /dev/null
RUN source "$HOME/.profile" && cargo install --quiet cargo-edit

# install tmux plugin manager
RUN git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm
COPY ./.tmux.conf $HOME/.tmux.conf
RUN TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins/" $HOME/.tmux/plugins/tpm/bin/install_plugins

# install lunarvim dependencies
RUN bash <(curl --proto '=https' --tlsv1.2 -sSfLo- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh)
RUN source "$HOME/.profile" && nvm install v18.7.0 --silent

# install lunarvim
RUN source $HOME/.profile && bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) -y > /dev/null
COPY ./config.lua $HOME/.config/lvim/
RUN source $HOME/.profile && lvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'

# install local kubernetes tools
RUN echo 'alias k=kubectl' >>~/.bashrc
RUN echo 'complete -o default -F __start_kubectl k' >>~/.bashrc



# CMD [ "/sbin/init" ]
ENTRYPOINT [ "/sbin/init" ]
