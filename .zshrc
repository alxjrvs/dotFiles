export EDITOR="code -w"

# Clear scrollback
printf '\n%.0s' {1..100}

# Autocorrection
setopt CORRECT

# Vi keybindings
bindkey -v

# Homebrew completions
fpath+=("$(brew --prefix)/share/zsh/site-functions")

# Sheldon plugins (adds zsh-completions to fpath)
eval "$(sheldon source)"

# Completions (must be after fpath extensions and sheldon)
autoload -Uz compinit && compinit

# Starship prompt
eval "$(starship init zsh)"

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# zoxide
eval "$(zoxide init zsh)"

# Aliases
alias c="clear"
alias q="exit"
alias gs="git status"
alias gpr='git pull --rebase'

# asdf default packages
export ASDF_GEM_DEFAULT_PACKAGES_FILE=~/dotFiles/.default-gems
export ASDF_NPM_DEFAULT_PACKAGES_FILE=~/dotFiles/.default-npm-packages

# PATH
export PATH="/opt/homebrew/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# Android SDK
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools

# Colored man pages
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;44;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;32m'
