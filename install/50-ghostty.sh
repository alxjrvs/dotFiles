#!/usr/bin/env bash
# install/50-ghostty.sh — Ghostty CLI shim (Darwin only).
# Ports sync.rs: step_ghostty.
# Tags: ghostty
# Sourced by sync.

# ── Self-contained helpers ────────────────────────────────────────────────────
if [[ -z "${__DOT_SYNC_SOURCED:-}" ]]; then
  os_kind() {
    case "$(uname -s)" in
      Darwin) printf 'darwin\n' ;;
      Linux) printf 'linux\n' ;;
      *) printf 'unknown\n' ;;
    esac
  }
fi

_ghostty_tags() { printf 'ghostty\n'; }

_ghostty_run() {
  if [[ "$(os_kind)" != "darwin" ]]; then
    return 0
  fi

  printf '\n==> Ghostty CLI shim\n'
  local app_bin="/Applications/Ghostty.app/Contents/MacOS/ghostty"
  if [[ ! -e "$app_bin" ]]; then
    # shellcheck disable=SC2016  # backticks are literal text in the message
    printf '\033[0;33m  \xe2\x86\x92 Ghostty.app not found — `brew bundle` should install it. Skipping shim.\033[0m\n'
    return 0
  fi

  local shim_dir="${HOME}/.local/bin"
  local shim="${shim_dir}/ghostty"
  mkdir -p "$shim_dir"

  # Already points at the right target?
  if [[ -L "$shim" ]]; then
    local existing
    existing=$(readlink "$shim" 2> /dev/null || true)
    if [[ "$existing" == "$app_bin" ]]; then
      printf '\033[0;32m  \xe2\x9c\x93 ghostty CLI shim already in place\033[0m\n'
      return 0
    fi
    rm -f "$shim"
  elif [[ -e "$shim" ]]; then
    # Plain file or directory — back up.
    mv "$shim" "${shim}.bak"
    printf '\033[0;33m  \xe2\x86\x92 existing non-symlink at %s backed up to %s.bak\033[0m\n' "$shim" "$shim"
  fi

  ln -s "$app_bin" "$shim"
  printf '\033[0;32m  \xe2\x9c\x93 ghostty shim -> %s\033[0m\n' "$shim"
}
