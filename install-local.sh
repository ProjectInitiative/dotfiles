
# COPY .bashrc and other configs
 echo 'PATH="$PATH:$HOME/.local/bin"' >> $HOME/.profile

# install rust
 sh <(curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs) -q -y > /dev/null
 source "$HOME/.profile" && cargo install --quiet cargo-edit

# install tmux plugin manager
 git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm
 TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins/" $HOME/.tmux/plugins/tpm/bin/install_plugins

# install lunarvim dependencies
 bash <(curl --proto '=https' --tlsv1.2 -sSfLo- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh)
 source "$HOME/.profile" && nvm install v18.7.0 --silent

# install lunarvim
 source $HOME/.profile && bash <(curl -s https://raw.githubusercontent.com/lunarvim/lunarvim/master/utils/installer/install.sh) -y > /dev/null
 source $HOME/.profile && lvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync'

# install local kubernetes tools
 echo 'alias k=kubectl' >>~/.bashrc
 echo 'complete -o default -F __start_kubectl k' >>~/.bashrc


