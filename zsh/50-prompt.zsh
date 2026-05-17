# Powerline prompt — rendered by `dotctl prompt-render` (Rust binary).
# All ANSI / OSC8 / Nord palette logic lives in dotctl/src/prompt.rs.
# This file is just the precmd glue: refresh the git cache when state
# changed, then ask dotctl for the prompt string.

setopt promptsubst

# zsh/stat: fast mtime checks without forking stat(1)
zmodload -F zsh/stat b:zstat 2> /dev/null

_render_prompt() {
  local _need_sync=0 _head_mtime="" _index_mtime=""

  [[ "$PWD" != "$_prompt_last_pwd" ]] && _need_sync=1

  if [[ -n "$GIT_DIR" ]]; then
    _head_mtime=$(zstat +mtime "$GIT_DIR/HEAD" 2> /dev/null)
    _index_mtime=$(zstat +mtime "$GIT_DIR/index" 2> /dev/null)
    if [[ "$_head_mtime" != "$_prompt_last_head_mtime" ]] || \
       [[ "$_index_mtime" != "$_prompt_last_index_mtime" ]]; then
      _need_sync=1
    fi
  fi

  if (( _need_sync )); then
    dotctl git-data
    PROMPT="$(dotctl prompt-render)"
    _prompt_last_pwd="$PWD"
    _prompt_last_head_mtime="$_head_mtime"
    _prompt_last_index_mtime="$_index_mtime"
  else
    # Background refresh so next prompt sees fresh data.
    (dotctl git-data &) 2> /dev/null
  fi
}
precmd_functions+=(_render_prompt)

# Transient prompt + pre-compute next prompt (eliminates blink).
# Collapse current line to U+276F on accept; pre-compute next prompt.
_transient_accept_line() {
  local _next="$(dotctl prompt-render)"
  PROMPT=$'%{\e[0m%}❯ '
  zle reset-prompt
  PROMPT="$_next"
  zle .accept-line
}
zle -N accept-line _transient_accept_line
