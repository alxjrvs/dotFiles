export EDITOR="nvim"
export VISUAL="$EDITOR"
export MANPAGER="nvim +Man!"
export LANG=en_US.UTF-8
export LESS='-RFX'
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# Machine-local secrets (not in git)
[[ -f ~/.secrets ]] && source ~/.secrets

# Autocorrection
setopt CORRECT

# History
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt EXTENDED_HISTORY
setopt HIST_REDUCE_BLANKS

# Vi keybindings
bindkey -v
KEYTIMEOUT=10

# Vi mode cursor shape
function zle-keymap-select {
  if [[ $KEYMAP == vicmd ]]; then
    echo -ne '\e[1 q'  # block cursor in normal mode
  else
    echo -ne '\e[5 q'  # beam cursor in insert mode
  fi
}
zle -N zle-keymap-select
# Beam cursor on new prompt
zle-line-init() { echo -ne '\e[5 q' }
zle -N zle-line-init

# Homebrew completions
fpath+=(/opt/homebrew/share/zsh/site-functions)

autoload -Uz add-zsh-hook

# Sheldon plugins (adds zsh-completions to fpath)
eval "$(sheldon source)"

# Atuin shell history
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# History substring search keybindings
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

# Syntax highlighting theme (Jack Kirby CMYK) — F-Sy-H overrides
typeset -A FAST_HIGHLIGHT_STYLES
FAST_HIGHLIGHT_STYLES[default]='fg=#e6edf3'
FAST_HIGHLIGHT_STYLES[command]='fg=#4db8cc'
FAST_HIGHLIGHT_STYLES[alias]='fg=#4db8cc'
FAST_HIGHLIGHT_STYLES[function]='fg=#d06cb8'
FAST_HIGHLIGHT_STYLES[builtin]='fg=#4db8cc'
FAST_HIGHLIGHT_STYLES[reserved-word]='fg=#d06cb8'
FAST_HIGHLIGHT_STYLES[unknown-token]='fg=#e05050'
FAST_HIGHLIGHT_STYLES[precommand]='fg=#d06cb8,underline'
FAST_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#d4b84a'
FAST_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#d4b84a'
FAST_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#d4b84a'
FAST_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#d48040'
FAST_HIGHLIGHT_STYLES[back-quoted-argument]='fg=#d48040'
FAST_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#8b949e'
FAST_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#8b949e'
FAST_HIGHLIGHT_STYLES[globbing]='fg=#d48040'
FAST_HIGHLIGHT_STYLES[redirection]='fg=#4db8cc'
FAST_HIGHLIGHT_STYLES[commandseparator]='fg=#4db8cc'
FAST_HIGHLIGHT_STYLES[assign]='fg=#d4b84a'
FAST_HIGHLIGHT_STYLES[comment]='fg=#8b949e,italic'
FAST_HIGHLIGHT_STYLES[path]='fg=#e6edf3,underline'

# Completions (must be after fpath extensions and sheldon)
autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(Nm+1) ]]; then
  compinit
else
  compinit -C
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

if command -v starship &>/dev/null; then
  eval "$(starship init zsh)"

  # Transient prompt: collapse previous prompts to minimal ❯
  # Preserves the typed command on screen (BUFFER is printed before reset).
  _transient_prompt_save="$PROMPT"

  _transient_restore_prompt() {
    PROMPT="$_transient_prompt_save"
  }
  precmd_functions+=(_transient_restore_prompt)

  _transient_accept_line() {
    # Print the current command so it stays visible after prompt reset
    local cmd="$BUFFER"
    PROMPT=$'%F{green}\u276f%f '
    zle .reset-prompt
    # Put the command back into the buffer so zsh executes it
    zle -U "$cmd"
    BUFFER="$cmd"
    CURSOR=${#BUFFER}
    zle .accept-line
  }
  zle -N accept-line _transient_accept_line
fi

# fzf shell integration (modern)
if command -v fzf &>/dev/null; then
  eval "$(fzf --zsh)" 2>/dev/null
fi
export FZF_DEFAULT_OPTS='--layout=reverse --border --height=40% --color=bg+:#3b4252,bg:#2e3440,spinner:#81a1c1,hl:#a3be8c,fg:#d8dee9,header:#a3be8c,info:#ebcb8b,pointer:#81a1c1,marker:#81a1c1,prompt:#81a1c1'
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always {}' --preview-window right:50%"
export FZF_ALT_C_OPTS="--preview 'eza --icons -T {} | head -20'"

# zoxide
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# Aliases
alias c="clear"
alias q="exit"

# Git
alias gs="git status"
alias gp="git push"
alias gpr='git pull --rebase'
alias gco='git checkout'
alias gd="git diff"
alias gds="git diff --staged"
alias gc="git commit"
alias ga="git add"
alias gaa="git add --all"
alias gb="git branch"
alias gl="git log --oneline -10"
alias lg="lazygit"

# Navigation
alias ..="cd .."
alias ...="cd ../.."
alias dots="cd ~/dotFiles"

# Enhanced tools (eza + bat)
alias ls="eza --icons --group-directories-first"
alias la="eza --icons --group-directories-first -la --git"
alias ll="eza --icons --group-directories-first -lh --git"
alias lt="eza --icons --group-directories-first -T --level=2"
alias tree="eza --icons --group-directories-first -T"
alias cat="bat --style=plain"

# Editor
alias v="nvim"
alias vi="nvim"
alias vim="nvim"

# System
alias env-sync="~/dotFiles/sync.sh"
claude-fix() { claude -p "Fix the following issue without committing: $*"; }

# Functions
function mkcd()   { mkdir -p "$1" && cd "$1" }
function cdroot() { cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in git repo"; return 1; } }
function sz()     { du -sh "${@:-.}" | sort -hr }


# mise (tool version manager)
command -v mise &>/dev/null && eval "$(mise activate zsh)"

# direnv (per-directory environment)
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# Colored man pages (CMYK)
export LESS_TERMCAP_mb=$'\e[1;35m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33;46m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;35m'

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# Push prompt to bottom of terminal on new shell
(( LINES > 0 )) && printf '\n%.0s' {1..$LINES}
