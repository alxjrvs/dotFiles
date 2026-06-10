#!/usr/bin/env bash
# install/60-claude.sh — Claude Code CLI install.
# Tags: claude
# Sourced by sync; not standalone — helpers (os_kind) come from sync, which
# exports them before sourcing this module.

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
      # claude.ai is not in the sandbox allowedDomains, so an in-session
      # reinstall dies at DNS with a generic curl error — name the cause.
      printf '\033[0;31m  \xe2\x9c\x97 Claude Code CLI install failed — if this ran inside a Claude Code session, the installer domain is sandbox-blocked; run from a regular terminal\033[0m\n' >&2
      return 1
    fi
  fi
}
