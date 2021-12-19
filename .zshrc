export ZSH=~/.oh-my-zsh

export EDITOR="code -w"

printf '\n%.0s' {1..100}

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
source ~/.p10k.zsh
ZSH_THEME=powerlevel10k/powerlevel10k
autoload -U promptinit; promptinit
export UPDATE_ZSH_DAYS=1

# Enable autocorrection
ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Add wisely, as too many plugins slow down shell startup.
plugins=(
  rake
  git
  docker
  npm
  rails
  brew
  zsh-z
  bundler
  ruby
  macos
  jsontools
  node
  pip
  web-search
  zsh-autosuggestions
  colored-man-pages
  colorize
  common-aliases
  copyfile
)

source $ZSH/oh-my-zsh.sh

# My useful aliases
alias c="clear"
alias q="exit"
alias gs="git status"
alias gpr='git pull --rebase'
local ret_status="%(?:%{$fg[yellow]%}=> :%{$fg[red]%}=> %s)"

bindkey -v

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
