# Powerline prompt — rendered by `dot prompt-render` (shell script).
# All ANSI / OSC8 / Nord palette logic lives in prompt/prompt-render.
# This file is just the precmd glue: refresh the git cache when state
# changed, then ask dot for the prompt string.

setopt promptsubst

# zsh/stat: fast mtime checks without forking stat(1)
zmodload -F zsh/stat b:zstat 2> /dev/null

# git-data cache directory (mirrors prompt/git-data git_cache_path()).
# Pure parameter expansion — no fork.
_dot_git_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/git-data"

# Read the GIT_DIR line from the cache file `dot git-data` just wrote and
# stash it in the shell-local `_dot_git_dir` for the mtime fast path.
#
# IMPORTANT: this is deliberately `_dot_git_dir`, NOT `GIT_DIR`. GIT_DIR is a
# magic environment variable git itself honors; leaking it into the
# interactive env would make `git` operate on the wrong repo after a cd.
# We never export, and never name it GIT_DIR.
#
# `dot git-data` runs in the foreground before this, so the newest file in
# the cache dir is USUALLY ours — but background refreshes from other
# sessions/repos race it (Claude Code fires them constantly), so a cache is
# accepted only when its GIT_TOPLEVEL actually contains $PWD. The few newest
# files are scanned. Pure-zsh glob + line reads; no fork.
_dot_read_git_dir() {
  _dot_git_dir=""
  local _cache _line _dir _top
  # Newest cache files first (om = order by mtime, descending).
  local -a _caches=("$_dot_git_cache_dir"/*.sh(Nom))
  for _cache in "${(@)_caches[1,4]}"; do
    [[ -r "$_cache" ]] || continue
    _dir="" _top=""
    while IFS= read -r _line; do
      case "$_line" in
        # Strip the KEY='...' wrapper (values are single-quoted by git-data).
        GIT_DIR=*) _dir="${${_line#GIT_DIR=\'}%\'}" ;;
        GIT_TOPLEVEL=*)
          _top="${${_line#GIT_TOPLEVEL=\'}%\'}"
          break # TOPLEVEL is emitted after DIR — both are in hand
          ;;
      esac
    done < "$_cache"
    if [[ -n "$_top" && -n "$_dir" ]] &&
      [[ "$PWD" == "$_top" || "$PWD" == "$_top"/* ]]; then
      _dot_git_dir="$_dir"
      return
    fi
  done
}

_render_prompt() {
  local _need_sync=0 _head_mtime="" _index_mtime=""

  [[ "$PWD" != "$_prompt_last_pwd" ]] && _need_sync=1

  if [[ -n "$_dot_git_dir" ]]; then
    _head_mtime=$(zstat +mtime "$_dot_git_dir/HEAD" 2> /dev/null)
    _index_mtime=$(zstat +mtime "$_dot_git_dir/index" 2> /dev/null)
    if [[ "$_head_mtime" != "$_prompt_last_head_mtime" ]] || \
       [[ "$_index_mtime" != "$_prompt_last_index_mtime" ]]; then
      _need_sync=1
    fi
  fi

  if (( _need_sync )); then
    # SKIP_PR: the foreground refresh runs before the prompt draws — an
    # expired PR TTL here used to mean a ~1s synchronous gh call right after
    # every commit. Stale PR data is served; the background refresh below
    # (without the flag) keeps it current.
    DOT_GIT_DATA_SKIP_PR=1 dot git-data
    PROMPT="$(dot prompt-render)"
    # Refresh the fast-path git dir from the freshly written cache.
    _dot_read_git_dir
    _head_mtime=$(zstat +mtime "$_dot_git_dir/HEAD" 2> /dev/null)
    _index_mtime=$(zstat +mtime "$_dot_git_dir/index" 2> /dev/null)
    _prompt_last_pwd="$PWD"
    _prompt_last_head_mtime="$_head_mtime"
    _prompt_last_index_mtime="$_index_mtime"
  elif [[ -n "$_dot_git_dir" ]]; then
    # Steady state inside a repo: HEAD/index unchanged and same dir. Kick a
    # background refresh so time-based data (PR status TTL) stays current
    # without blocking the prompt. Outside a repo (_dot_git_dir empty) there
    # is nothing time-based to refresh — no kick.
    (dot git-data &) 2> /dev/null
  fi
}
precmd_functions+=(_render_prompt)

# Transient prompt + pre-compute next prompt (eliminates blink).
# Collapse current line to U+276F on accept; pre-compute next prompt.
_transient_accept_line() {
  local _next="$(dot prompt-render)"
  PROMPT=$'%{\e[0m%}❯ '
  zle reset-prompt
  PROMPT="$_next"
  zle .accept-line
}
zle -N accept-line _transient_accept_line
