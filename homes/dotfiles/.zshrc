# ~/.zshrc

# Set up the prompt
autoload -Uz promptinit
promptinit
prompt adam1

# Use emacs keybindings even if our EDITOR is set to vi
bindkey -e

# Keep 1000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

# Use modern completion system
autoload -Uz compinit
compinit

zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select=2
eval "$(dircolors -b)"
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true

zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# Load aliases and shortcuts if existent.
[ -f "$HOME/.aliasrc" ] && source "$HOME/.aliasrc"

# Environment variables
export GPG_TTY=$(tty)
export VISUAL="/home/kpzak/.cargo/bin/hx"
export EDITOR="$VISUAL"
export KUBECONFIG=~/.kube/config
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
export PATH=$PATH:/usr/local/go/bin
export PATH=/home/kpzak/.tiup/bin:$PATH
export PATH="$PATH:/home/linuxbrew/.linuxbrew/bin"

# NVM setup
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Aliases
alias refresh='source ~/.zshrc'
alias vim="nvim"
alias make='make -j $(nproc)'
alias loc='git ls-files | xargs wc -l'
alias k='kubectl'
alias kx='kubectl ctx'
alias kn='kubectl ns'
alias rm-pv="kubectl get pv | grep Released | awk '$1 {print$1}' | while read vol; do kubectl delete pv/${vol}; done"
alias tailscale-up='sudo tailscale up --login-server https://ts.projectinitiative.io --accept-routes'
alias wgon='nmcli connection up wg0'
alias wgoff='nmcli connection down wg0'
alias vpn='while ! sshuttle --dns --to-ns 172.16.1.1 -r manage.projecti.org 0/0; do sleep 1; done'
alias hotspot='sshuttle --dns --to-ns 172.16.1.1 -r termux 0/0'
alias upgrade='sudo apt update && sudo apt upgrade -y'
alias hog='du -ahP . -d 1'
alias ap='ansible-playbook'
alias mount-gluster="sudo mount -t nfs pve.projecti.org:/mnt/main-pool /mnt/main-pool/"
alias grep="rg"
alias ls="exa"
alias ll="exa -al"
alias cat="bat"

# Functions
copy() { 
    xclip -selection clipboard -i < "$1"
}

aws() {
    command aws --endpoint-url https://ssd.s3.us-east-1.projectinitiative.io $@
}

# Distrobox
if [ -f /run/.containerenv ] || [ -f /.dockerenv ]; then
    if [ -e /usr/local/bin/bind-user.sh ]; then
        /usr/local/bin/bind-user.sh
    fi
fi
alias devbox='distrobox-enter devbox -- zsh -l'

# Kubectl completion
source <(kubectl completion zsh)
compdef __start_kubectl k

# Setup Rust
source "$HOME/.cargo/env"

# Zsh-specific settings
setopt HIST_IGNORE_DUPS
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_SPACE

# If you want to use Oh My Zsh, uncomment these lines and add desired plugins
# export ZSH="$HOME/.oh-my-zsh"
# ZSH_THEME="robbyrussell"
# plugins=(git docker kubectl)
# source $ZSH/oh-my-zsh.sh

# Syntax highlighting (install zsh-syntax-highlighting package first)
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Auto suggestions (install zsh-autosuggestions package first)
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# Initialize atuin (shell history tool)
eval "$(atuin init zsh)"
