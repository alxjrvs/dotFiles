#!/usr/bin/env bash
# install/85-lefthook.sh — lefthook install for the dotfiles repo.
# Ports sync.rs: step_lefthook.
# Tags: lefthook
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

_lefthook_tags() { printf 'lefthook\n'; }

_lefthook_run() {
  printf '\n==> Lefthook (this repo)\n'
  if ! command -v lefthook > /dev/null 2>&1; then
    printf '\033[0;33m  \xe2\x86\x92 lefthook not found — should have been installed by mise (mise.toml)\033[0m\n'
    return 0
  fi

  if lefthook install \
    --working-directory "${DOTFILES_DIR}" \
    > /dev/null 2>&1; then
    printf '\033[0;32m  \xe2\x9c\x93 lefthook hooks installed in %s/.git/hooks/\033[0m\n' "${DOTFILES_DIR}"
  else
    printf '\033[0;33m  \xe2\x86\x92 lefthook install failed — check '"'"'lefthook install --force'"'"' manually\033[0m\n'
  fi
}
