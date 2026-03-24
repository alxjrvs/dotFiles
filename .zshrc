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
    echo -ne '\e[1 q'  # blinking block cursor in insert mode
  fi
}
zle -N zle-keymap-select
# Blinking block cursor on new prompt
zle-line-init() { echo -ne '\e[1 q' }
zle -N zle-line-init

# Homebrew completions
fpath+=(/opt/homebrew/share/zsh/site-functions)

autoload -Uz add-zsh-hook

# Cached init helper — regenerates when the binary is updated.
# Avoids subprocess spawn on every shell startup by caching init output.
_cached_eval() {
  local name="$1" cmd="$2" bin="$3"
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-init/${name}.zsh"
  if [[ ! -f "$cache" || "$bin" -nt "$cache" ]]; then
    mkdir -p "${cache:h}"
    command ${=cmd} > "$cache"
  fi
  source "$cache"
}

# Sheldon plugins (adds zsh-completions to fpath)
_cached_eval sheldon "sheldon source" "$(command -v sheldon)"

# Atuin shell history
command -v atuin &>/dev/null && _cached_eval atuin "atuin init zsh" "$(command -v atuin)"

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

# Prompt setup (replaces starship)
setopt promptsubst
source ~/dotFiles/theme.sh

# _prompt_repo_dir — renders repo+GH icon OR fallback directory segment
# Reads: GIT_REPO_NAME, GIT_REPO_HTTPS, GIT_PR_STATUS, GIT_PR_URL (set by precmd)
# Leaves bg at NOVA_SEG_BG (#434C5E) for the git segment to follow.
function _prompt_repo_dir() {
  local _fg=$'%{\e[38;2;'   _bg=$'%{\e[48;2;'   _m=$'m%}'   _rst=$'%{\e[0m%}'
  local _ul=$'%{\e[4m%}'     _noul=$'%{\e[24m%}'
  local _osc8_open=$'%{\e]8;;'   _osc8_mid=$'\a%}'   _osc8_close=$'%{\e]8;;\a%}'

  # Glyph constants (unicode — written by Python)
  local _A=$''   # U+E0B0 right triangle
  local _O=$''   # U+E0BA opening wedge
  local _GH=$''  # U+F09B GitHub

  # Color triplets
  local TERM_R=46  TERM_G=52  TERM_B=64      # #2E3440 terminal bg
  local PN2_R=67   PN2_G=76   PN2_B=94       # #434C5E segment bg
  local SS1_R=216  SS1_G=222  SS1_B=233      # #D8DEE9 Snow Storm 1
  local FG_L_R=236 FG_L_G=239 FG_L_B=244    # #ECEFF4 light text
  local FG_D_R=46  FG_D_G=52  FG_D_B=64     # #2E3440 dark text

  # PR status -> icon bg/fg
  local pr_bg_r=$SS1_R  pr_bg_g=$SS1_G  pr_bg_b=$SS1_B
  local pr_fg_r=$FG_D_R pr_fg_g=$FG_D_G pr_fg_b=$FG_D_B

  case "$GIT_PR_STATUS" in
    pass)
      pr_bg_r=$NOVA_PR_PASS_R    pr_bg_g=$NOVA_PR_PASS_G    pr_bg_b=$NOVA_PR_PASS_B
      pr_fg_r=$FG_D_R pr_fg_g=$FG_D_G pr_fg_b=$FG_D_B
      ;;
    pending)
      pr_bg_r=$NOVA_PR_PENDING_R pr_bg_g=$NOVA_PR_PENDING_G pr_bg_b=$NOVA_PR_PENDING_B
      pr_fg_r=$FG_D_R pr_fg_g=$FG_D_G pr_fg_b=$FG_D_B
      ;;
    fail)
      pr_bg_r=$NOVA_PR_FAIL_R    pr_bg_g=$NOVA_PR_FAIL_G    pr_bg_b=$NOVA_PR_FAIL_B
      pr_fg_r=$FG_L_R pr_fg_g=$FG_L_G pr_fg_b=$FG_L_B
      ;;
  esac

  # Directory fallback: last 2 path components with ~/
  local cwd=${PWD/#$HOME/\~}
  local dir_display
  if [[ "$cwd" == */*/* ]]; then
    dir_display="${cwd:h:t}/${cwd:t}"
  else
    dir_display="$cwd"
  fi

  local o=""

  if [[ -n "$GIT_REPO_NAME" ]]; then
    # Opening edge: terminal bg -> PR icon bg
    o="${o}${_bg}${TERM_R};${TERM_G};${TERM_B}${_m}${_fg}${pr_bg_r};${pr_bg_g};${pr_bg_b}${_m}${_O}"
    # GH icon segment
    if [[ -n "$GIT_PR_URL" ]]; then
      o="${o}${_bg}${pr_bg_r};${pr_bg_g};${pr_bg_b}${_m}${_fg}${pr_fg_r};${pr_fg_g};${pr_fg_b}${_m} ${_osc8_open}${GIT_PR_URL}${_osc8_mid}${_GH}${_osc8_close} "
    else
      o="${o}${_bg}${pr_bg_r};${pr_bg_g};${pr_bg_b}${_m}${_fg}${pr_fg_r};${pr_fg_g};${pr_fg_b}${_m} ${_GH} "
    fi
    # Transition: PR icon bg -> PN2 for repo name
    o="${o}${_bg}${PN2_R};${PN2_G};${PN2_B}${_m}${_fg}${pr_bg_r};${pr_bg_g};${pr_bg_b}${_m}${_A}"
    # Repo name (underlined, OSC8 hyperlinked)
    o="${o}${_fg}${FG_L_R};${FG_L_G};${FG_L_B}${_m} ${_ul}${_osc8_open}${GIT_REPO_HTTPS}${_osc8_mid}${GIT_REPO_NAME}${_osc8_close}${_noul} "
  else
    # Dir only: opening edge from terminal bg into PN2
    o="${o}${_bg}${TERM_R};${TERM_G};${TERM_B}${_m}${_fg}${PN2_R};${PN2_G};${PN2_B}${_m}${_O}"
    o="${o}${_bg}${PN2_R};${PN2_G};${PN2_B}${_m}${_fg}${FG_L_R};${FG_L_G};${FG_L_B}${_m} ${dir_display} "
  fi

  print -rn -- "$o"
}
# _prompt_git_seg — renders git branch + status pips
# Reads: GIT_IS_REPO, GIT_BRANCH, STATUSLINE_WORKTREE,
#        GIT_STASH_COUNT, GIT_CONFLICT_COUNT, GIT_UNTRACKED_COUNT,
#        GIT_UNSTAGED_COUNT, GIT_STAGED_COUNT, GIT_AHEAD, GIT_BEHIND
# Expects NOVA_* color vars from theme.sh (already sourced).
function _prompt_git_seg() {
  [[ -z "$GIT_IS_REPO" ]] && return
  local o="" prev_r prev_g prev_b
  local _fg=$'%{\e[38;2;'   _bg=$'%{\e[48;2;'   _m=$'m%}'   _rst=$'%{\e[0m%}'
  local _A=$'\ue0b0'  # U+E0B0 powerline right-triangle

  # Branch pill: space on SEG_BG, then arrow into BRANCH bg
  o+="${_bg}${NOVA_SEG_BG_R};${NOVA_SEG_BG_G};${NOVA_SEG_BG_B}${_m} "
  o+="${_bg}${NOVA_BRANCH_R};${NOVA_BRANCH_G};${NOVA_BRANCH_B}${_m}"
  o+="${_fg}${NOVA_SEG_BG_R};${NOVA_SEG_BG_G};${NOVA_SEG_BG_B}${_m}${_A}"
  o+="${_fg}${NOVA_BG_R};${NOVA_BG_G};${NOVA_BG_B}${_m} ${GIT_BRANCH} "
  prev_r=$NOVA_BRANCH_R; prev_g=$NOVA_BRANCH_G; prev_b=$NOVA_BRANCH_B

  # Worktree cell (only if STATUSLINE_WORKTREE is set)
  if [[ -n "$STATUSLINE_WORKTREE" ]]; then
    o+="${_bg}${NOVA_WORKTREE_R};${NOVA_WORKTREE_G};${NOVA_WORKTREE_B}${_m}"
    o+="${_fg}${prev_r};${prev_g};${prev_b}${_m}${_A}"
    o+="${_fg}${NOVA_BG_R};${NOVA_BG_G};${NOVA_BG_B}${_m} ${STATUSLINE_WORKTREE} "
    prev_r=$NOVA_WORKTREE_R; prev_g=$NOVA_WORKTREE_G; prev_b=$NOVA_WORKTREE_B
  fi

  # Pip helper (inner function)
  _render_pip() {
    o+="${_bg}${1};${2};${3}${_m}${_fg}${prev_r};${prev_g};${prev_b}${_m}${_A}"
    o+="${_fg}${NOVA_BG_R};${NOVA_BG_G};${NOVA_BG_B}${_m} ${4} "
    prev_r=$1; prev_g=$2; prev_b=$3
  }

  local has_pips=0
  (( GIT_STASH_COUNT > 0 ))     && { has_pips=1; _render_pip $NOVA_GIT_STASH_R $NOVA_GIT_STASH_G $NOVA_GIT_STASH_B "\$${GIT_STASH_COUNT}"; }
  (( GIT_CONFLICT_COUNT > 0 ))  && { has_pips=1; _render_pip $NOVA_GIT_CONFLICT_R $NOVA_GIT_CONFLICT_G $NOVA_GIT_CONFLICT_B "!${GIT_CONFLICT_COUNT}"; }
  (( GIT_UNTRACKED_COUNT > 0 )) && { has_pips=1; _render_pip $NOVA_GIT_UNTRACKED_R $NOVA_GIT_UNTRACKED_G $NOVA_GIT_UNTRACKED_B "?${GIT_UNTRACKED_COUNT}"; }
  (( GIT_UNSTAGED_COUNT > 0 ))  && { has_pips=1; _render_pip $NOVA_GIT_UNSTAGED_R $NOVA_GIT_UNSTAGED_G $NOVA_GIT_UNSTAGED_B "~${GIT_UNSTAGED_COUNT}"; }
  (( GIT_STAGED_COUNT > 0 ))    && { has_pips=1; _render_pip $NOVA_GIT_STAGED_R $NOVA_GIT_STAGED_G $NOVA_GIT_STAGED_B "+${GIT_STAGED_COUNT}"; }
  (( GIT_AHEAD > 0 ))           && { has_pips=1; _render_pip $NOVA_GIT_AHEAD_R $NOVA_GIT_AHEAD_G $NOVA_GIT_AHEAD_B $'\u2191'"${GIT_AHEAD}"; }
  (( GIT_BEHIND > 0 ))          && { has_pips=1; _render_pip $NOVA_GIT_BEHIND_R $NOVA_GIT_BEHIND_G $NOVA_GIT_BEHIND_B $'\u2193'"${GIT_BEHIND}"; }
  (( has_pips == 0 ))            && _render_pip $NOVA_GIT_CLEAN_R $NOVA_GIT_CLEAN_G $NOVA_GIT_CLEAN_B $'\u2713'

  # Closing arrow
  o+="${_rst}${_fg}${prev_r};${prev_g};${prev_b}${_m}${_A}${_rst}"
  print -rn -- "$o"
}

# Prompt rendering (runs before each prompt)
# Strategy: render instantly from stale cache, refresh async for next prompt.
_render_prompt() {
  local _cache="/tmp/git-data-cache-$(id -u).sh"

  # Source existing cache immediately (stale is fine — instant render)
  [[ -f "$_cache" ]] && source "$_cache"

  # Render prompt now from whatever cache we have
  local repo_seg=$(_prompt_repo_dir)
  local git_seg=$(_prompt_git_seg)
  PROMPT="${repo_seg}${git_seg} "

  # Refresh cache in background for next prompt (non-blocking)
  (sh ~/dotFiles/starship-scripts/git-data.sh &) 2>/dev/null
}
precmd_functions+=(_render_prompt)

# Transient prompt — collapses previous prompt to a single glyph
_transient_accept_line() {
  PROMPT=$'%{\e[0m%}\u276f '
  zle reset-prompt
  zle .accept-line
}
zle -N accept-line _transient_accept_line

# fzf shell integration (modern)
if command -v fzf &>/dev/null; then
  _cached_eval fzf "fzf --zsh" "$(command -v fzf)"
fi
export FZF_DEFAULT_OPTS='--layout=reverse --border --height=40% --color=bg+:#3b4252,bg:#2e3440,spinner:#81a1c1,hl:#a3be8c,fg:#d8dee9,header:#a3be8c,info:#ebcb8b,pointer:#81a1c1,marker:#81a1c1,prompt:#81a1c1'
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always {}' --preview-window right:50%"
export FZF_ALT_C_OPTS="--preview 'eza --icons -T {} | head -20'"

# zoxide
command -v zoxide &>/dev/null && _cached_eval zoxide "zoxide init zsh" "$(command -v zoxide)"

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
command -v mise &>/dev/null && _cached_eval mise "mise activate zsh" "$(command -v mise)"

# direnv (per-directory environment)
command -v direnv &>/dev/null && _cached_eval direnv "direnv hook zsh" "$(command -v direnv)"

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
