#!/usr/bin/env bats
# Unit tests for lib/common.sh — the shared helpers (os_kind, resolve_dotfiles_dir,
# link) that both sync and doctor depend on. Run locally with `mise x -- bats test/`
# or `bats test/`; also run in CI (.github/workflows/lint.yml).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=../lib/common.sh
  source "${REPO}/lib/common.sh"
  TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/common.XXXXXX")"
}

teardown() {
  rm -rf "$TMP"
}

@test "os_kind matches the running platform" {
  case "$(uname -s)" in
    Darwin) expected=darwin ;;
    Linux) expected=linux ;;
    *) expected=unknown ;;
  esac
  run os_kind
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "resolve_dotfiles_dir honors \$DOTFILES_DIR when it holds a Brewfile" {
  mkdir -p "$TMP/df"
  touch "$TMP/df/Brewfile"
  DOTFILES_DIR="$TMP/df" run resolve_dotfiles_dir
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP/df" ]
}

@test "resolve_dotfiles_dir rejects a dir without a Brewfile sentinel" {
  mkdir -p "$TMP/nope" "$TMP/home"
  DOTFILES_DIR="$TMP/nope" _DOTFILES_SELF_DIR="" HOME="$TMP/home" run resolve_dotfiles_dir
  [ "$status" -ne 0 ]
}

@test "link creates a missing symlink" {
  echo content > "$TMP/src"
  run link "$TMP/src" "$TMP/dst"
  [ "$status" -eq 0 ]
  [ -L "$TMP/dst" ]
  [ "$(readlink "$TMP/dst")" = "$TMP/src" ]
}

@test "link is idempotent on an already-correct symlink" {
  echo content > "$TMP/src"
  ln -s "$TMP/src" "$TMP/dst"
  run link "$TMP/src" "$TMP/dst"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already linked"* ]]
}

@test "link skips a conflicting file in skip mode" {
  echo existing > "$TMP/dst"
  echo content > "$TMP/src"
  LINK_MODE=skip run link "$TMP/src" "$TMP/dst"
  [ "$status" -eq 0 ]
  [ ! -L "$TMP/dst" ]
  [ "$(cat "$TMP/dst")" = existing ]
}

@test "link overwrites a conflicting file in overwrite mode" {
  echo existing > "$TMP/dst"
  echo content > "$TMP/src"
  LINK_MODE=overwrite run link "$TMP/src" "$TMP/dst"
  [ "$status" -eq 0 ]
  [ -L "$TMP/dst" ]
  [ "$(readlink "$TMP/dst")" = "$TMP/src" ]
}

@test "link --dry-run reports the action but creates nothing" {
  echo content > "$TMP/src"
  DRY_RUN=1 run link "$TMP/src" "$TMP/dst"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/dst" ]
  [[ "$output" == *"would be linked"* ]]
}
