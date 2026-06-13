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

# ── Output palette ────────────────────────────────────────────────────────────
# Single source of the ANSI color/glyph strings, shared by the standalone
# scripts (doctor, watchtower). The `_p_*` functions are the raw printers — the
# escape sequences live here exactly once. The unprefixed names are what scripts
# call: watchtower uses them as-is; doctor re-wraps _warn/_fail/_fixed to also
# bump its counters (it needs the totals for its exit code — see doctor).
_p_hdr() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
_p_ok() { printf '\033[0;32m  \xe2\x9c\x93 %s\033[0m\n' "$*"; }
_p_warn() { printf '\033[0;33m  \xe2\x86\x92 %s\033[0m\n' "$*"; }
_p_fail() { printf '\033[0;31m  \xe2\x9c\x97 %s\033[0m\n' "$*" >&2; }
_p_fixed() { printf '\033[0;36m  \xe2\x9c\x82 %s\033[0m\n' "$*"; }
_p_note() { printf '    %s\n' "$*"; }

_hdr() { _p_hdr "$@"; }
_ok() { _p_ok "$@"; }
_warn() { _p_warn "$@"; }
_fail() { _p_fail "$@"; }
_crit() { _p_fail "$@"; } # watchtower's name for a red-x line
_fixed() { _p_fixed "$@"; }
_note() { _p_note "$@"; }

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

  # Dry-run: report the action that WOULD be taken and mutate nothing. Must sit
  # ahead of the create-if-missing branch below — LINK_MODE=skip does NOT stop
  # that branch from creating a missing link, so this is the only safe gate.
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    if [[ ! -e "$dst" && ! -L "$dst" ]]; then
      printf '\033[0;36m  ~ %s would be linked\033[0m\n' "$label"
    else
      printf '\033[0;36m  ~ %s exists and is not our symlink — would resolve via LINK_MODE\033[0m\n' "$label"
    fi
    return 0
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
