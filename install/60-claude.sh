#!/usr/bin/env bash
# install/60-claude.sh — Claude Code CLI install.
# Ports sync.rs: step_claude.
# Tags: claude
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

_claude_tags() { printf 'claude\n'; }

_claude_run() {
  printf '\n==> Claude Code\n'
  if command -v claude > /dev/null 2>&1; then
    local ver
    ver=$(claude --version 2> /dev/null | head -1 || true)
    printf '\033[0;32m  \xe2\x9c\x93 Claude Code CLI installed (%s)\033[0m\n' "$ver"
  else
    printf '\033[0;33m  \xe2\x86\x92 Installing Claude Code CLI (native installer)...\033[0m\n'
    if bash -c "$(curl -fsSL https://claude.ai/install.sh)"; then
      printf '\033[0;32m  \xe2\x9c\x93 Claude Code CLI installed\033[0m\n'
    else
      printf '\033[0;31m  \xe2\x9c\x97 Claude Code CLI install failed — re-run or install manually\033[0m\n' >&2
    fi
  fi
}
