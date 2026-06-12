#!/usr/bin/env bash
# lib/common.sh — helpers shared by the standalone scripts (sync, doctor,
# install/95-prune.sh). Sourced, never executed; sets no shell options.
#
# Callers set _DOTFILES_SELF_DIR to their own repo-root directory before
# sourcing, so resolve_dotfiles_dir can use it as a fallback candidate.

# os_kind: "darwin" | "linux" | "unknown"
os_kind() {
  case "$(uname -s)" in
    Darwin) printf 'darwin\n' ;;
    Linux) printf 'linux\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

# resolve_dotfiles_dir: $DOTFILES_DIR → caller's $_DOTFILES_SELF_DIR → ~/dotFiles.
# Returns the first that is a directory containing a Brewfile.
resolve_dotfiles_dir() {
  local candidates=(
    "${DOTFILES_DIR:-}"
    "${_DOTFILES_SELF_DIR:-}"
    "${HOME}/dotFiles"
  )
  local c
  for c in "${candidates[@]}"; do
    [[ -n "$c" && -d "$c" && -f "${c}/Brewfile" ]] && printf '%s\n' "$c" && return 0
  done
  return 1
}
