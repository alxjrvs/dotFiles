# shellcheck shell=bash
# Shared helpers for install/*.sh modules.
# Sourced by sync.sh before any module — modules rely on these being defined.
# Do not execute directly.

# ── Colors & log helpers ────────────────────────────────────────────
GREEN='\033[0;32m' YELLOW='\033[0;33m' RED='\033[0;31m' DIM='\033[2m' NC='\033[0m'
ok() { printf "${GREEN}  ✓ %s${NC}\n" "$1"; }
warn() { printf "${YELLOW}  → %s${NC}\n" "$1"; }
fail() { printf "${RED}  ✗ %s${NC}\n" "$1"; }
dim() { printf "${DIM}  - %s${NC}\n" "$1"; }

# ── should_run — check if a section should execute ─────────────────
# With no --only flag, everything runs. With --only, a section runs if
# any of its tags appear in the comma-separated ONLY list.
# Usage: should_run tag1 [tag2 ...]
should_run() {
  [ -z "$ONLY" ] && return 0
  local tag
  for tag in "$@"; do
    echo ",$ONLY," | grep -q ",$tag," && return 0
  done
  return 1
}

# ── link() — idempotent symlink with interactive conflict resolution ─
# IMPORTANT: the interactive prompt is load-bearing. Do not refactor to
# auto-overwrite or skip without user opt-in (see CLAUDE.md guardrails).
link() {
  local src="$1" dst="$2" label="$3"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    dim "$label already linked"
    return
  fi

  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    ln -sfn "$src" "$dst"
    warn "$label linked"
    return
  fi

  # Something else exists — resolve conflict
  fail "$label: $dst exists but is not our symlink"
  local choice="$LINK_MODE"
  if [ -z "$choice" ]; then
    printf "       Overwrite with symlink to %s? [o]verwrite / [s]kip: " "$src"
    read -r choice
  fi
  case "$choice" in
    o | O | overwrite)
      mv "$dst" "${dst}.bak"
      ln -sfn "$src" "$dst"
      warn "$label overwritten (backup at ${dst}.bak)"
      ;;
    *)
      ok "$label skipped"
      ;;
  esac
}