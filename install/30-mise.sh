#!/usr/bin/env bash
# install/30-mise.sh — mise toolchain install/upgrade (Darwin only).
# Tags: mise
# Sourced by sync; not standalone — helpers (os_kind) come from sync, which
# exports them before sourcing this module.

_mise_tags() { printf 'mise\n'; }

_mise_run() {
  if [[ "$(os_kind)" != "darwin" ]]; then
    return 0
  fi

  printf '\n==> mise tools\n'

  # Pin mise to the repo's mise.toml explicitly. Nothing in
  # bootstrap.sh -> dot -> sync chdirs to the repo, so CWD-based config
  # discovery finds nothing on a fresh machine. MISE_CONFIG_FILE forces
  # the correct file regardless of CWD or whether the
  # ~/.config/mise/config.toml symlink exists yet.
  local mise_toml="${DOTFILES_DIR}/mise.toml"
  if [[ ! -f "$mise_toml" ]]; then
    printf '\033[0;31m  \xe2\x9c\x97 mise.toml not found at %s — skipping\033[0m\n' "$mise_toml" >&2
    return 0
  fi
  export MISE_CONFIG_FILE="$mise_toml"

  # Trust the pinned config (idempotent).
  mise trust "$mise_toml" 2> /dev/null || true

  if [[ "${SYNC_UPGRADE:-0}" == "1" ]]; then
    printf '\033[0;33m  \xe2\x86\x92 Upgrading mise tools (mise upgrade)...\033[0m\n'
    mise upgrade 2> /dev/null || true
  fi

  printf '\033[0;33m  \xe2\x86\x92 Installing tools from mise.toml...\033[0m\n'
  mise install

  # mise install creates ~/.local/share/mise/shims on a fresh machine.
  # sync's PATH setup ran before this module and gated on the dir's
  # existence, so later modules (lefthook, gh) would miss mise-managed
  # binaries within this same sync run. Re-export the shims dir onto PATH
  # unconditionally now — sync sources modules in one shell, so this
  # propagates to every module that runs after mise.
  local mise_shims="${HOME}/.local/share/mise/shims"
  if [[ -d "$mise_shims" ]]; then
    case ":${PATH}:" in
      *":${mise_shims}:"*) ;;
      *) PATH="${mise_shims}:${PATH}" ;;
    esac
    export PATH
  fi

  printf '\033[0;32m  \xe2\x9c\x93 mise tools up to date\033[0m\n'
}
