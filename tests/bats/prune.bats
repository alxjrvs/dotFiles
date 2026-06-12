#!/usr/bin/env bats
# Behavioral tests for install/95-prune.sh — the one subsystem that deletes
# files (the guarded .bak cleanup). Pass-level coverage pins filesystem effects
# (not message text) so the collect/confirm/apply internals can be refactored
# safely — the .bak guard must never delete a backup that's the only copy.
# HOME points at a temp dir; tests source the script standalone.

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

load 'helpers'

setup() {
  scrub_git_env
  TDIR="$(mktemp -d "${TMPDIR:-/tmp}/bats.XXXXXX")"
  export HOME="$TDIR"
}
teardown() { rm -rf "$TDIR"; }

# Source 95-prune.sh standalone (no __DOT_SYNC_SOURCED) against a fake repo.
_setup_prune() {
  export DOTFILES_DIR="$TDIR/repo"
  mkdir -p "$DOTFILES_DIR"
  : > "$DOTFILES_DIR/Brewfile"
  unset __DOT_SYNC_SOURCED
  source "$ROOT/install/95-prune.sh"
}

# ── confirm default: non-TTY must NOT mean yes ───────────────────────────────
# A cron/CI run with no terminal answering "yes" to every delete is the
# opposite of link()'s safe non-interactive skip.
@test "prune ask: non-TTY defaults to skip, not delete" {
  _setup_prune
  run _prune_ask_yes "Delete everything?" < /dev/null
  [ "$status" -ne 0 ]
}

@test "prune ask-mode pass leaves files in place on non-TTY" {
  _setup_prune
  export PRUNE_MODE=ask
  echo tracked > "$DOTFILES_DIR/.zshrc"
  ln -s "$DOTFILES_DIR/.zshrc" "$TDIR/.zshrc"
  echo backup > "$TDIR/.zshrc.bak"
  run _prune_backups "$TDIR" < /dev/null
  [ "$status" -eq 0 ]
  [ -e "$TDIR/.zshrc.bak" ]
}

# ── pass effects under auto / dry ────────────────────────────────────────────
@test "prune backups: dry mode deletes nothing" {
  _setup_prune
  export PRUNE_MODE=dry
  echo tracked > "$DOTFILES_DIR/.zshrc"
  ln -s "$DOTFILES_DIR/.zshrc" "$TDIR/.zshrc"
  echo backup > "$TDIR/.zshrc.bak"
  run _prune_backups "$TDIR"
  [ "$status" -eq 0 ]
  [ -e "$TDIR/.zshrc.bak" ]
}

@test "prune backups: auto deletes guarded-safe .bak, keeps unsafe" {
  _setup_prune
  export PRUNE_MODE=auto
  # Safe: live sibling is a symlink into the dotfiles repo.
  echo tracked > "$DOTFILES_DIR/.zshrc"
  ln -s "$DOTFILES_DIR/.zshrc" "$TDIR/.zshrc"
  echo backup > "$TDIR/.zshrc.bak"
  # Unsafe: sibling is a plain file — .bak may be the only copy.
  echo plain > "$TDIR/.vimrc"
  echo backup > "$TDIR/.vimrc.bak"
  run _prune_backups "$TDIR"
  [ "$status" -eq 0 ]
  [ ! -e "$TDIR/.zshrc.bak" ]
  [ -e "$TDIR/.vimrc.bak" ]
}

# ── standalone flag plumbing (dot prune must preserve these) ─────────────────
@test "prune standalone: --dry-run flag reaches PRUNE_MODE" {
  echo tracked > "$TDIR/tracked"
  ln -s "$ROOT/Brewfile" "$TDIR/.zshrc"
  echo backup > "$TDIR/.zshrc.bak"
  export DOTFILES_DIR="$ROOT"
  run "$ROOT/install/95-prune.sh" --dry-run
  [ "$status" -eq 0 ]
  [ -e "$TDIR/.zshrc.bak" ]
}

@test "dot prune dispatches to 95-prune.sh directly (flags survive)" {
  grep -q 'install/95-prune.sh' "$ROOT/dot"
  ! grep -qE 'prune\) exec .*sync.*--only=prune' "$ROOT/dot"
}

# ── .bak guard (_prune_bak_is_safe) unit tests ───────────────────────────────
# A .bak is only safe to delete when its live sibling is a symlink into the
# dotfiles repo (link() displaced a tracked file). Otherwise the .bak may be
# the only copy and must be kept.

@test "prune .bak guard: sibling symlink into dotfiles repo is safe to delete" {
  _setup_prune
  echo tracked > "$DOTFILES_DIR/.zshrc"
  ln -s "$DOTFILES_DIR/.zshrc" "$TDIR/.zshrc"
  echo backup > "$TDIR/.zshrc.bak"
  run _prune_bak_is_safe "$TDIR/.zshrc.bak"
  [ "$status" -eq 0 ]
}

@test "prune .bak guard: sibling is a plain file -> kept (not safe)" {
  _setup_prune
  echo plain > "$TDIR/.zshrc"
  echo backup > "$TDIR/.zshrc.bak"
  run _prune_bak_is_safe "$TDIR/.zshrc.bak"
  [ "$status" -ne 0 ]
}

@test "prune .bak guard: sibling missing -> kept (.bak may be only copy)" {
  _setup_prune
  echo backup > "$TDIR/.zshrc.bak"
  run _prune_bak_is_safe "$TDIR/.zshrc.bak"
  [ "$status" -ne 0 ]
}

@test "prune .bak guard: sibling symlink outside the repo -> kept (not safe)" {
  _setup_prune
  echo elsewhere > "$TDIR/other"
  ln -s "$TDIR/other" "$TDIR/.zshrc"
  echo backup > "$TDIR/.zshrc.bak"
  run _prune_bak_is_safe "$TDIR/.zshrc.bak"
  [ "$status" -ne 0 ]
}
