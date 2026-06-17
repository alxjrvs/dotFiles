#!/usr/bin/env bash
# hook: claude_statusline — clone the statusline repo beside the dotfiles repo, run install.
# Data: repo=<git url>  → $BOTU_repo
_claude_statusline_dir() { printf '%s' "$(cd "$BOTU_CONFIG/.." && pwd)/claude-statusline"; }
_claude_statusline_apply() {
  _hdr "claude-statusline"
  local url="https://${BOTU_repo:-github.com/alxjrvs/claude-statusline}.git" dir
  dir="$(_claude_statusline_dir)"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    _note "would clone ${url} → ${dir} and run install.sh"
    return 0
  fi
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" pull --ff-only -q 2> /dev/null && _ok "statusline updated"
  else git clone -q "$url" "$dir" && _ok "statusline cloned → ${dir}"; fi
  [[ -x "$dir/install.sh" ]] && (cd "$dir" && ./install.sh) > /dev/null 2>&1 && _ok "statusline installed"
}
_claude_statusline_verify() {
  _hdr "claude-statusline"
  if [[ -x "$HOME/.local/bin/claude-statusline" ]]; then _ok "statusline on PATH"; else _warn "statusline missing — botu apply --only=claude_statusline"; fi
}
_claude_statusline_fix() { _claude_statusline_apply; }
