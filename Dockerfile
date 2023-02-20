FROM docker.io/ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive
ARG TZ="America/Chicago"
SHELL ["/bin/bash", "-c"]

ARG DOTFILES="/src/dotfiles"
ADD . ${DOTFILES}

# update apt cache and upgrade packages
RUN apt-get update -qq && apt-get upgrade -qq -y > /dev/null && apt-get install -qq -y apt-utils bc curl dialog diffutils findutils gnupg2 less libnss-myhostname libvte-2.9[0-9]-common libvte-common lsof ncurses-base passwd pinentry-curses procps sudo time wget util-linux > /dev/null

# install base dependencies
RUN apt-get install -qq -y ca-certificates git fuse > /dev/null

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
RUN apt-get update -qq > /dev/null

# install tmux
RUN apt-get install -qq -y tmux > /dev/null

# use host docker and podman
# RUN apt-get install -qq -y ca-certificates curl gnupg lsb-release > /dev/null
# RUN mkdir -p /etc/apt/keyrings
# RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
# RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
# RUN apt-get update -qq > /dev/null && apt-get install -qq -y docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null
RUN ln -s /usr/bin/distrobox-host-exec /usr/local/bin/docker
RUN ln -s /usr/bin/distrobox-host-exec /usr/local/bin/podman

# install python
RUN apt-get install -qq -y python3 python3-pip > /dev/null

# install kubernetes
RUN apt-get install -y -qq kubectl helm > /dev/null
RUN kubectl completion bash | tee /etc/bash_completion.d/kubectl > /dev/null

# install hashicorp packages
RUN apt-get install -y -qq gnupg software-properties-common > /dev/null
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
RUN apt-get update -qq > /dev/null && apt-get install -y -qq vagrant terraform packer > /dev/null

# install go
RUN curl --proto '=https' --tlsv1.2 -sSfL https://go.dev/dl/go1.19.linux-amd64.tar.gz | tar -C /usr/local -xz

# USER LEVEL INSTALLS
# create installer user
RUN groupadd -g 1111 installer && useradd -u 1111 -g 1111 -m -s /bin/bash installer && echo 'installer ALL=(ALL) NOPASSWD:ALL' >>/etc/sudoers
USER installer
RUN cp ${DOTFILES}/.bashrc $HOME/.bashrc

# install go binaries
# install hcloud
RUN /usr/local/go/bin/go install github.com/hetznercloud/cli/cmd/hcloud@latest > /dev/null 2>&1

# install rust
RUN sh <(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs) -q -y > /dev/null 2>&1
RUN source "$HOME/.profile" && cargo install --quiet cargo-edit

# install rust binaries
RUN source "$HOME/.profile" && cargo install ripgrep > /dev/null

# install helix
RUN source "$HOME/.profile" && ${DOTFILES}/install-helix.sh > /dev/null

# install zellij
RUN source "$HOME/.profile" && ${DOTFILES}/install-zellij.sh > /dev/null

# install homebrew
USER root
RUN groupadd -g 4200 linuxbrew && useradd -u 4200 -g 4200 -m -s /bin/bash linuxbrew && echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >>/etc/sudoers
USER linuxbrew
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)" > /dev/null 2>&1
USER root


# # install tmux plugin manager
# RUN git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm
# COPY ./.tmux.conf $HOME/.tmux.conf
# RUN TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins/" $HOME/.tmux/plugins/tpm/bin/install_plugins

# # install lunarvim dependencies
# RUN bash <(curl --proto '=https' --tlsv1.2 -sSfLo- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh)
# RUN source "$HOME/.profile" && nvm install v18.7.0 --silent

# # install lunarvim
# RUN source $HOME/.profile && bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) -y > /dev/null
# COPY ./config.lua $HOME/.config/lvim/
# RUN source $HOME/.profile && lvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'

# # install local kubernetes tools
# RUN echo 'alias k=kubectl' >>~/.bashrc
# RUN echo 'complete -o default -F __start_kubectl k' >>~/.bashrc



# CMD [ "/sbin/init" ]
# ENTRYPOINT [ "/sbin/init" ]

# install misc essentials
# RUN apt-get install -qq -y ripgrep > /dev/null
