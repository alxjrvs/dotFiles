#!/usr/bin/env bash
# lib/common.sh — helpers shared by the standalone scripts (sync, doctor).
# Sourced, never executed; sets no shell options.
#
# Callers set _DOTFILES_SELF_DIR to their own repo-root directory before
# sourcing, so resolve_dotfiles_dir can use it as a fallback candidate.
#
# link() lives here (not in sync) so both sync and doctor --fix create/repair
# symlinks with identical semantics — a single source of truth for the one
# operation that deletes files at the destination.

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

# link SRC DST: idempotent symlink with LINK_MODE conflict handling.
# Uses LINK_MODE env ("interactive"|"overwrite"|"skip").
link() {
  local src="$1" dst="$2"
  local label="${dst#"${HOME}"/}"

  # Already correctly linked?
  if [[ -L "$dst" ]]; then
    local target
    target=$(readlink "$dst" 2> /dev/null || true)
    if [[ "$target" == "$src" ]]; then
      printf '\033[2m  - %s already linked\033[0m\n' "$label"
      return 0
    fi
  fi

  if [[ ! -e "$dst" && ! -L "$dst" ]]; then
    # Destination missing — just create.
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    printf '\033[0;33m  \xe2\x86\x92 %s linked\033[0m\n' "$label"
    return 0
  fi

  # Conflict: something else exists at dst.
  printf '\033[0;31m  \xe2\x9c\x97 %s: %s exists but is not our symlink\033[0m\n' "$label" "$dst" >&2
  local choice
  case "${LINK_MODE:-interactive}" in
    overwrite) choice="o" ;;
    skip) choice="s" ;;
    *)
      # Interactive default — but never block on a non-TTY (unattended
      # bootstrap). Fall back to skip + a loud warning so the conflict is
      # visible rather than hanging on read.
      if [[ ! -t 0 ]]; then
        choice="s"
        printf '\033[0;33m  \xe2\x9a\xa0 %s: non-interactive — skipping conflict (existing %s left in place)\033[0m\n' "$label" "$dst" >&2
      else
        printf '       Overwrite with symlink to %s? [o]verwrite / [s]kip: ' "$src"
        read -r choice || choice="s"
      fi
      ;;
  esac

  case "$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')" in
    o | overwrite)
      # No backup — the canonical content lives in this git repo. A displaced
      # pre-existing file is the user's to recover (it isn't tracked here).
      rm -rf -- "$dst"
      ln -s "$src" "$dst"
      printf '\033[0;33m  \xe2\x86\x92 %s overwritten\033[0m\n' "$label"
      ;;
    *)
      printf '\033[0;32m  \xe2\x9c\x93 %s skipped\033[0m\n' "$label"
      ;;
  esac
}
