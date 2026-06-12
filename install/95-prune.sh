#!/usr/bin/env bash
# install/95-prune.sh — cleanup: stale `.bak` backups left by link() overwrites.
# (Claude Code worktrees + workers are Claude Code's lifecycle to manage, not
# the dotfiles provisioner's — those passes were removed.)
#
# Modes (env vars or flags when run standalone):
#   PRUNE_MODE=auto   — delete without prompting (AutoYes)
#   PRUNE_MODE=dry    — list only, never delete (DryRun)
#   default           — prompt [Y/n], default yes (AskDefaultYes)
#
# Tags: prune
# Runnable standalone: ./install/95-prune.sh [-y|--yes] [-n|--dry-run]
# Also sourced by sync (calls _prune_run directly).

set -euo pipefail

# mapfile below needs bash 4+; Apple's /bin/bash is 3.2 forever, so a fresh
# machine running this standalone must fail with a real message instead of
# aborting mid-clean (brew "bash" is in the Brewfile).
if ((BASH_VERSINFO[0] < 4)); then
  printf '95-prune: bash >= 4 required (this is %s) — brew install bash\n' \
    "${BASH_VERSION}" >&2
  # return when sourced (sync), exit when standalone.
  # shellcheck disable=SC2317
  return 1 2> /dev/null || exit 1
fi

# ── Shared helpers ────────────────────────────────────────────────────────────
# When sourced by sync, os_kind/resolve_dotfiles_dir are already defined (sync
# sources lib/common.sh and exports them). Standalone, source the lib directly.
if [[ -z "${__DOT_SYNC_SOURCED:-}" ]]; then
  _PRUNE_SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  # shellcheck source=../lib/common.sh
  _DOTFILES_SELF_DIR="${_PRUNE_SELF_DIR%/install}"
  source "${_PRUNE_SELF_DIR%/install}/lib/common.sh"
fi

_prune_tags() { printf 'prune\n'; }

# ── Helpers ───────────────────────────────────────────────────────────────────

# Prompt "Delete these X? [Y/n]", default yes on a TTY. On a non-TTY
# (cron/CI session) the safe answer is NO — same convention as
# link()'s non-interactive conflict skip. Returns 0=yes, 1=no.
_prune_ask_yes() {
  local question="$1"
  if [[ ! -t 0 ]]; then
    printf '\033[0;33m  \xe2\x9a\xa0 Non-interactive; skipping (run with -y to delete unattended)\033[0m\n' >&2
    return 1
  fi
  printf '       %s [Y/n]: ' "$question" >&2
  local reply
  read -r reply || reply=""
  case "$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')" in
    "" | y | yes) return 0 ;;
    *) return 1 ;;
  esac
}

# Shared list → confirm → apply skeleton for the prune passes.
# Caller fills the parallel globals _PRUNE_ITEMS (raw values handed to ACTION)
# and _PRUNE_LABELS (display strings), then calls:
#   _prune_confirm_apply NOUN QUESTION ACTION [VERB]
# Empty item list prints a green "No NOUN" and returns. Otherwise the list is
# shown, PRUNE_MODE gates the apply (auto=yes, dry=no, ask=_prune_ask_yes),
# and ACTION <raw> runs per item: rc 0 = done, rc 2 = kept (ACTION printed its
# own reason), anything else = failed. VERB (default "Deleted") labels the
# summary line.
_prune_confirm_apply() {
  local noun="$1" question="$2" action="$3" verb="${4:-Deleted}"
  local n="${#_PRUNE_ITEMS[@]}"

  if [[ "$n" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 No %s\033[0m\n' "$noun"
    return 0
  fi

  printf '\033[0;33m  Found %d %s:\033[0m\n' "$n" "$noun"
  local i
  for ((i = 0; i < n; i++)); do
    printf '\033[2m    - %s\033[0m\n' "${_PRUNE_LABELS[$i]}"
  done

  local go=0
  case "${PRUNE_MODE:-ask}" in
    auto) go=1 ;;
    dry) go=0 ;;
    *)
      _prune_ask_yes "$question" && go=1 || go=0
      ;;
  esac
  if [[ "$go" -eq 0 ]]; then
    printf '\033[2m  - Skipped (nothing removed)\033[0m\n'
    return 0
  fi

  local applied=0 failed=0 kept=0 rc
  for ((i = 0; i < n; i++)); do
    rc=0
    "$action" "${_PRUNE_ITEMS[$i]}" || rc=$?
    case "$rc" in
      0) applied=$((applied + 1)) ;;
      2) kept=$((kept + 1)) ;;
      *)
        printf '\033[0;33m  \xe2\x86\x92 failed: %s\033[0m\n' "${_PRUNE_LABELS[$i]}" >&2
        failed=$((failed + 1))
        ;;
    esac
  done
  if [[ "$failed" -eq 0 ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 %s %d %s\033[0m\n' "$verb" "$applied" "$noun"
  else
    printf '\033[0;33m  \xe2\x86\x92 %s %d, %d failed\033[0m\n' "$verb" "$applied" "$failed"
  fi
  if [[ "$kept" -gt 0 ]]; then
    printf '\033[0;33m  \xe2\x9a\xa0 Kept %d (see reasons above)\033[0m\n' "$kept"
  fi
}

# True for a backup filename.
_is_backup_file() {
  local name
  name=$(basename "$1")
  # *.bak
  [[ "$name" == *.bak ]] && return 0
  # *.bak-<something> (non-empty suffix)
  if [[ "$name" == *".bak-"* ]]; then
    local after="${name##*.bak-}"
    [[ -n "$after" ]] && return 0
  fi
  # *.bak.<anything>
  [[ "$name" == *".bak."* ]] && return 0
  return 1
}

# Compute the non-.bak "live" sibling path for a backup file. link() creates
# backups as "${dst}.bak", so for "foo.bak" the sibling is "foo". For the
# ".bak-<suffix>" / ".bak.<suffix>" variants we strip from the ".bak" marker.
# Echoes the sibling path; empty if none can be derived.
_prune_bak_sibling() {
  local path="$1" name dir base
  dir=$(dirname "$path")
  name=$(basename "$path")
  if [[ "$name" == *.bak ]]; then
    base="${name%.bak}"
  elif [[ "$name" == *".bak-"* || "$name" == *".bak."* ]]; then
    base="${name%%.bak*}"
  else
    return 0
  fi
  [[ -z "$base" ]] && return 0
  printf '%s/%s\n' "$dir" "$base"
}

# Resolve the dotfiles repo dir for the .bak guard. Sourced by sync →
# $DOTFILES_DIR is exported; standalone → resolve_dotfiles_dir() is defined in
# the guard block above. Cached in _PRUNE_DOTFILES_DIR. Empty if unresolvable.
_prune_dotfiles_dir() {
  if [[ -n "${_PRUNE_DOTFILES_DIR+x}" ]]; then
    printf '%s\n' "$_PRUNE_DOTFILES_DIR"
    return 0
  fi
  local resolved="${DOTFILES_DIR:-}"
  if [[ -z "$resolved" ]] && declare -f resolve_dotfiles_dir > /dev/null 2>&1; then
    resolved=$(resolve_dotfiles_dir 2> /dev/null || true)
  fi
  _PRUNE_DOTFILES_DIR="$resolved"
  printf '%s\n' "$_PRUNE_DOTFILES_DIR"
}

# Guard: a .bak is safe to delete only when its live sibling is a symlink that
# points into the dotfiles repo (i.e. link() displaced a real file we still own
# a tracked copy of). If the sibling is absent, a plain file, or a symlink
# pointing elsewhere, the .bak may be the only copy of that config — keep it.
# Returns 0 = safe to delete, 1 = should be skipped.
_prune_bak_is_safe() {
  local bak="$1"
  local sibling target df
  sibling=$(_prune_bak_sibling "$bak")
  # No derivable sibling → be conservative, keep it.
  [[ -z "$sibling" ]] && return 1
  # Sibling missing entirely → the .bak may be the only copy.
  [[ -e "$sibling" || -L "$sibling" ]] || return 1
  # Sibling must be a symlink (link() replaces conflicts with a symlink).
  [[ -L "$sibling" ]] || return 1
  target=$(readlink "$sibling" 2> /dev/null || true)
  [[ -n "$target" ]] || return 1
  # Resolve relative link targets against the sibling's directory.
  case "$target" in
    /*) ;;
    *) target="$(dirname "$sibling")/${target}" ;;
  esac
  df=$(_prune_dotfiles_dir)
  [[ -n "$df" ]] || return 1
  case "$target" in
    "$df"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Walk DIR up to DEPTH levels, calling cb (a function name) on each file.
# Skips .git, node_modules, target, share, Caches, installs, and symlinks.
_prune_walk() {
  local dir="$1" depth="$2" cb="$3"
  [[ "$depth" -le 0 ]] && return 0
  [[ -d "$dir" ]] || return 0
  local entry name
  while IFS= read -r -d '' entry; do
    name=$(basename "$entry")
    # Skip noisy subtrees.
    case "$name" in
      .git | node_modules | target | share | Caches | installs) continue ;;
    esac
    # Skip symlinks (avoid loop into mise/cargo dirs).
    [[ -L "$entry" ]] && continue
    if [[ -d "$entry" ]]; then
      _prune_walk "$entry" $((depth - 1)) "$cb"
    elif [[ -f "$entry" ]]; then
      "$cb" "$entry"
    fi
  done < <(find "$dir" -maxdepth 1 -mindepth 1 -print0 2> /dev/null)
}

# ── Pass 1: backup files ──────────────────────────────────────────────────────

_prune_collect_backup() {
  _is_backup_file "$1" && _PRUNE_BACKUPS+=("$1") || true
}

# Action: delete one .bak, guarded — a .bak whose live sibling is NOT a
# symlink into the dotfiles repo may be the only copy of a displaced config.
_prune_rm_backup() {
  local b="$1"
  if ! _prune_bak_is_safe "$b"; then
    printf '\033[0;33m  \xe2\x9a\xa0 keeping %s (sibling not a dotfiles symlink — may be the only copy)\033[0m\n' \
      "${b/#$HOME\//~/}" >&2
    return 2
  fi
  rm -f "$b" 2> /dev/null
}

_prune_backups() {
  local home="${1:-$HOME}"
  _PRUNE_BACKUPS=()

  # Scan roots and depths for .bak backups.
  _prune_walk "$home" 1 _prune_collect_backup
  _prune_walk "${home}/.config" 4 _prune_collect_backup
  _prune_walk "${home}/.claude" 4 _prune_collect_backup
  _prune_walk "${home}/.ssh" 1 _prune_collect_backup

  printf '\n==> Backup cleanup\n'
  _PRUNE_ITEMS=() _PRUNE_LABELS=()
  local b
  for b in "${_PRUNE_BACKUPS[@]+"${_PRUNE_BACKUPS[@]}"}"; do
    _PRUNE_ITEMS+=("$b")
    _PRUNE_LABELS+=("${b/#$home\//~/}")
  done
  _prune_confirm_apply "backup file(s)" "Delete these backups?" _prune_rm_backup
}

# ── Main entry ────────────────────────────────────────────────────────────────

_prune_run() {
  _prune_backups "${HOME}"
}

# ── Standalone execution (dot prune / ./install/95-prune.sh) ─────────────────
# When run directly (not sourced), parse flags and invoke _prune_run.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  for _prune_arg in "$@"; do
    case "$_prune_arg" in
      -y | --yes) PRUNE_MODE="auto" ;;
      -n | --dry-run) PRUNE_MODE="dry" ;;
    esac
  done
  unset _prune_arg
  export PRUNE_MODE="${PRUNE_MODE:-ask}"
  _prune_run
fi
