#!/usr/bin/env bash
# install/30-mise.sh — mise toolchain install/upgrade (Darwin only per Rust).
# Ports sync.rs: step_mise.
# Tags: mise
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

_mise_tags() { printf 'mise\n'; }

_mise_run() {
  if [[ "$(os_kind)" != "darwin" ]]; then
    return 0
  fi

  printf '\n==> mise tools\n'
  local mise_toml="${HOME}/.config/mise/config.toml"
  if [[ -f "$mise_toml" ]]; then
    mise trust "$mise_toml" 2> /dev/null || true
  fi

  if [[ "${SYNC_UPGRADE:-0}" == "1" ]]; then
    printf '\033[0;33m  \xe2\x86\x92 Upgrading mise tools (mise upgrade)...\033[0m\n'
    mise upgrade 2> /dev/null || true
  fi

  printf '\033[0;33m  \xe2\x86\x92 Installing tools from mise.toml...\033[0m\n'
  mise install
  printf '\033[0;32m  \xe2\x9c\x93 mise tools up to date\033[0m\n'
}
