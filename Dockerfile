FROM docker.io/ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive
ARG TZ="America/Chicago"
SHELL ["/bin/bash", "-c"]

ARG DOTFILES="/src/dotfiles"
ADD . ${DOTFILES}
# RUN ln -sf ${DOTFILES}/bin /usr/local/bin
RUN ln -sf ${DOTFILES}/bin/brew-up /usr/local/bin/brew-up
RUN ln -sf ${DOTFILES}/bin/bind-user.sh /usr/local/bin/bind-user.sh
# RUN ln -sf ${DOTFILES}/bin/setup-overlay.sh /usr/local/bin/setup-overlay.sh

# update apt cache and upgrade packages
RUN apt-get update -qq && apt-get upgrade -qq -y > /dev/null && apt-get install -qq -y apt-utils bc curl dialog diffutils findutils gnupg2 less libnss-myhostname libvte-2.9[0-9]-common libvte-common lsof ncurses-base passwd pinentry-curses procps sudo time wget util-linux > /dev/null

# install base dependencies
RUN apt-get install -qq -y ca-certificates git lsb-release fuse > /dev/null

# install dev essentials
RUN apt-get install -qq -y build-essential pkg-config openssl libssl-dev procps > /dev/null

# add apt keys
# google
RUN curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
# helm
RUN curl -fsSL https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
# microsoft
RUN wget wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
RUN dpkg -i packages-microsoft-prod.deb
RUN rm packages-microsoft-prod.deb
# update apt cache
RUN apt-get update -qq > /dev/null

# install tmux
RUN apt-get install -qq -y tmux > /dev/null

# use host docker and podman
RUN ln -sf /usr/bin/distrobox-host-exec /usr/local/bin/docker
RUN ln -sf /usr/bin/distrobox-host-exec /usr/local/bin/podman

# install python
RUN apt-get install -qq -y python3 python3-pip > /dev/null

# install dotnet and powershell
RUN apt-get install -qq -y dotnet-sdk-7.0 powershell

# install kubernetes
RUN apt-get install -y -qq kubectl helm > /dev/null
RUN kubectl completion bash | tee /etc/bash_completion.d/kubectl > /dev/null

# install hashicorp packages
# RUN apt-get install -y -qq gnupg software-properties-common > /dev/null
# RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
# RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
# RUN apt-get update -qq > /dev/null && apt-get install -y -qq vagrant terraform packer > /dev/null

# install go
RUN curl --proto '=https' --tlsv1.2 -sSfL https://go.dev/dl/go1.19.linux-amd64.tar.gz | tar -C /usr/local -xz


# USER LEVEL INSTALLS
# create installer user
RUN groupadd -g 1111 installer && useradd -u 1111 -g 1111 -m -s /bin/bash installer && echo 'installer ALL=(ALL) NOPASSWD:ALL' >>/etc/sudoers
USER installer
RUN ln -sf ${DOTFILES}/.bashrc $HOME/.bashrc
RUN mkdir -p $HOME/.config && ln -sf ${DOTFILES}/helix $HOME/.config/helix
# RUN ln -s ${DOTFILES}/.alacritty.yml $HOME/.alacritty.yml
RUN ln -sf ${DOTFILES}/.alacritty.yml $HOME/.alacritty.yml
# add safe directory
RUN sudo chown -R installer:installer ${DOTFILES} 
RUN git config --global --add safe.directory ${DOTFILES}


# install go binaries
# install hcloud
RUN /usr/local/go/bin/go install github.com/hetznercloud/cli/cmd/hcloud@latest > /dev/null 2>&1

# install rust
RUN sh <(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs) -q -y > /dev/null 2>&1
RUN source "$HOME/.profile" && cargo install --quiet sccache && source "$HOME/.profile" && RUSTC_WRAPPER=sccache cargo install --quiet cargo-edit cargo-info bacon speedtest-rs
# RUN source "$HOME/.profile" && cargo install --quiet sccache && source "$HOME/.profile" && RUSTC_WRAPPER=sccache cargo install --quiet cargo-edit cargo-info ripgrep bat exa bacon du-dust speedtest-rs gitui


# install homebrew
USER root
RUN groupadd -g 4200 linuxbrew && useradd -u 4200 -g 4200 -m -s /bin/bash linuxbrew && echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >>/etc/sudoers
USER linuxbrew
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install.sh)" > /dev/null 2>&1
RUN ln -sf ${DOTFILES}/Brewfile $HOME/Brewfile
RUN /home/linuxbrew/.linuxbrew/bin/brew tap Homebrew/bundle
RUN /usr/local/bin/brew-up
USER root


