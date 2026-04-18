export EDITOR="nvim"
export VISUAL="$EDITOR"
export MANPAGER="nvim +Man!"
export LANG=en_US.UTF-8
export LESS='-RFX'
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$PATH:$ANDROID_HOME/platform-tools"

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

# _prompt_repo_dir -- renders identity cell (repo OR CWD) + GH icon
# Shows repo name (linked, underlined) if in GH repo, else CWD path.
# Both use Snow Storm 1 bg. Repo wins when both exist.
# Reads: GIT_REPO_NAME, GIT_REPO_HTTPS, GIT_PR_STATUS, GIT_PR_URL, GIT_IS_REPO
function _prompt_repo_dir() {
  local _fg=$'%{\e[38;2;'   _bg=$'%{\e[48;2;'   _m=$'m%}'   _rst=$'%{\e[0m%}'
  local _ul=$'%{\e[4m%}'     _noul=$'%{\e[24m%}'
  local _osc8_open=$'%{\e]8;;'   _osc8_mid=$'\a%}'   _osc8_close=$'%{\e]8;;\a%}'

  # Glyph constants
  local _A=$'\ue0b0'   # U+E0B0 right triangle
  local _O=$'\ue0ba'   # U+E0BA opening wedge
  local _GH=$'\uf09b'  # U+F09B GitHub

  # Color triplets
  local TERM_R=46  TERM_G=52  TERM_B=64      # #2E3440 terminal bg
  local SS1_R=216  SS1_G=222  SS1_B=233      # #D8DEE9 Snow Storm 1
  local FG_L_R=236 FG_L_G=239 FG_L_B=244    # #ECEFF4 light text
  local FG_D_R=46  FG_D_G=52  FG_D_B=64     # #2E3440 dark text

  # PR status -> icon bg/fg (default: Nord 1 bg, white icon)
  local pr_bg_r=59   pr_bg_g=66   pr_bg_b=82
  local pr_fg_r=$FG_L_R  pr_fg_g=$FG_L_G  pr_fg_b=$FG_L_B

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

  # CWD: last 2 path components (fallback when no repo)
  local cwd=${PWD/#$HOME/\~}
  local dir_display
  if [[ "$cwd" == */*/* ]]; then
    dir_display="${cwd:h:t}/${cwd:t}"
  else
    dir_display="$cwd"
  fi

  local o=""

  # -- Identity cell (SS1 bg, dark text) -- opening wedge from terminal bg
  o+="${_bg}${TERM_R};${TERM_G};${TERM_B}${_m}${_fg}${SS1_R};${SS1_G};${SS1_B}${_m}${_O}"
  o+="${_bg}${SS1_R};${SS1_G};${SS1_B}${_m}${_fg}${FG_D_R};${FG_D_G};${FG_D_B}${_m}"

  if [[ -n "$GIT_REPO_NAME" ]]; then
    # Repo name: linked, underlined
    o+=" ${_ul}${_osc8_open}${GIT_REPO_HTTPS}${_osc8_mid}${GIT_REPO_NAME}${_osc8_close}${_noul} "
    # Identity -> GH icon on PR status bg
    o+="${_bg}${pr_bg_r};${pr_bg_g};${pr_bg_b}${_m}${_fg}${SS1_R};${SS1_G};${SS1_B}${_m}${_A}"
    if [[ -n "$GIT_PR_URL" ]]; then
      o+="${_fg}${pr_fg_r};${pr_fg_g};${pr_fg_b}${_m} ${_osc8_open}${GIT_PR_URL}${_osc8_mid}${_GH}${_osc8_close} "
    else
      o+="${_fg}${pr_fg_r};${pr_fg_g};${pr_fg_b}${_m} ${_GH} "
    fi
  else
    # CWD path (no link)
    o+=" ${dir_display} "
    if [[ -z "$GIT_IS_REPO" ]]; then
      # No git: close identity cell
      o+="${_rst}${_fg}${SS1_R};${SS1_G};${SS1_B}${_m}${_A}${_rst}"
    fi
  fi

  print -rn -- "$o"
}
# _prompt_git_seg -- renders git branch + status pips
# Reads: GIT_IS_REPO, GIT_BRANCH, GIT_REPO_NAME, GIT_PR_STATUS,
#        STATUSLINE_WORKTREE, GIT_STASH_COUNT, GIT_CONFLICT_COUNT,
#        GIT_UNTRACKED_COUNT, GIT_UNSTAGED_COUNT, GIT_STAGED_COUNT,
#        GIT_AHEAD, GIT_BEHIND
# Expects NOVA_* color vars from theme.sh (already sourced).
function _prompt_git_seg() {
  [[ -z "$GIT_IS_REPO" ]] && return
  local o="" prev_r prev_g prev_b
  local _fg=$'%{\e[38;2;'   _bg=$'%{\e[48;2;'   _m=$'m%}'   _rst=$'%{\e[0m%}'
  local _A=$'\ue0b0'  # U+E0B0 powerline right-triangle

  # Branch pill — white bg (Snow Storm 1), dark text
  local _BR_R=216 _BR_G=222 _BR_B=233
  local _BR_FG_R=46 _BR_FG_G=52 _BR_FG_B=64

  # Branch pill opening
  if [[ -n "$GIT_REPO_NAME" ]]; then
    # Arrow from GH icon cell (PR status bg) into branch
    local _pr_r=59 _pr_g=66 _pr_b=82
    case "$GIT_PR_STATUS" in
      pass)    _pr_r=$NOVA_PR_PASS_R;    _pr_g=$NOVA_PR_PASS_G;    _pr_b=$NOVA_PR_PASS_B ;;
      pending) _pr_r=$NOVA_PR_PENDING_R; _pr_g=$NOVA_PR_PENDING_G; _pr_b=$NOVA_PR_PENDING_B ;;
      fail)    _pr_r=$NOVA_PR_FAIL_R;    _pr_g=$NOVA_PR_FAIL_G;    _pr_b=$NOVA_PR_FAIL_B ;;
    esac
    o+="${_bg}${_BR_R};${_BR_G};${_BR_B}${_m}"
    o+="${_fg}${_pr_r};${_pr_g};${_pr_b}${_m}${_A}"
  else
    # Seamless from identity cell (both SS1) — invisible arrow
    o+="${_bg}${_BR_R};${_BR_G};${_BR_B}${_m}"
    o+="${_fg}${_BR_R};${_BR_G};${_BR_B}${_m}${_A}"
  fi
  o+="${_fg}${_BR_FG_R};${_BR_FG_G};${_BR_FG_B}${_m} ${GIT_BRANCH} "
  prev_r=$_BR_R; prev_g=$_BR_G; prev_b=$_BR_B

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

# Prompt rendering helpers
_build_prompt() {
  local _git_key=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
  local _git_hash=$(printf '%s' "$_git_key" | shasum -a 256 | cut -c1-12)
  local _cache="/tmp/git-data-cache-$(id -u)-${_git_hash}.sh"
  [[ -f "$_cache" ]] && source "$_cache"
  # Invalidate stale git data if CWD moved outside cached repo
  if [[ -n "$GIT_TOPLEVEL" ]] && [[ "$PWD" != "$GIT_TOPLEVEL"* ]]; then
    GIT_IS_REPO="" GIT_REPO_NAME="" GIT_BRANCH=""
  fi
  local repo_seg=$(_prompt_repo_dir)
  local git_seg=$(_prompt_git_seg)
  print -rn -- "${repo_seg}${git_seg} "
}

# zsh/stat: fast mtime checks without forking `stat(1)`
zmodload -F zsh/stat b:zstat 2>/dev/null

# Precmd: sync-refresh when PWD or git state (HEAD/index mtime) changed,
# otherwise keep the cheap async refresh path.
_render_prompt() {
  local _git_key=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
  local _git_hash=$(printf '%s' "$_git_key" | shasum -a 256 | cut -c1-12)
  local _cache="/tmp/git-data-cache-$(id -u)-${_git_hash}.sh"
  [[ -f "$_cache" ]] && source "$_cache"

  local _need_sync=0 _head_mtime="" _index_mtime=""

  [[ "$PWD" != "$_prompt_last_pwd" ]] && _need_sync=1

  if [[ -n "$GIT_DIR" ]]; then
    _head_mtime=$(zstat +mtime "$GIT_DIR/HEAD" 2>/dev/null)
    _index_mtime=$(zstat +mtime "$GIT_DIR/index" 2>/dev/null)
    if [[ "$_head_mtime" != "$_prompt_last_head_mtime" ]] || \
       [[ "$_index_mtime" != "$_prompt_last_index_mtime" ]]; then
      _need_sync=1
    fi
  fi

  if (( _need_sync )); then
    sh ~/dotFiles/scripts/git-data.sh
    PROMPT="$(_build_prompt)"
    _prompt_last_pwd="$PWD"
    _prompt_last_head_mtime="$_head_mtime"
    _prompt_last_index_mtime="$_index_mtime"
  else
    (sh ~/dotFiles/scripts/git-data.sh &) 2>/dev/null
  fi
}
precmd_functions+=(_render_prompt)

# Transient prompt + pre-compute next prompt (eliminates blink)
_transient_accept_line() {
  # Pre-compute next prompt from stale cache (instant)
  local _next="$(_build_prompt)"
  # Collapse current line to ❯
  PROMPT=$'%{\e[0m%}\u276f '
  zle reset-prompt
  # Set next prompt BEFORE command runs — no gap when it finishes
  PROMPT="$_next"
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
