export EDITOR="code -w"

# Clear scrollback
printf '\n%.0s' {1..100}

# Autocorrection
setopt CORRECT

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# Vi keybindings
bindkey -v
KEYTIMEOUT=1

# Homebrew completions
fpath+=("$(brew --prefix)/share/zsh/site-functions")

# Sheldon plugins (adds zsh-completions to fpath)
eval "$(sheldon source)"

# Completions (must be after fpath extensions and sheldon)
autoload -Uz compinit
if [ "$(find ~/.zcompdump -mtime +1 2>/dev/null)" ]; then
  compinit
else
  compinit -C
fi

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
export ASDF_NPM_DEFAULT_PACKAGES_FILE=~/.default-npm-packages

# Colored man pages
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;44;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;32m'

# bun completions
[ -s "/Users/jarvis/.oh-my-zsh/completions/_bun" ] && source "/Users/jarvis/.oh-my-zsh/completions/_bun"
