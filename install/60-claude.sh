#!/usr/bin/env bash
# install/60-claude.sh — Claude Code CLI install.
# Tags: claude
# Sourced by sync; not standalone — helpers (os_kind) come from sync, which
# exports them before sourcing this module.

_claude_tags() { printf 'claude\n'; }

# Register the user-scope `github` HTTP MCP server in ~/.claude.json. It points
# at the GitHub Copilot MCP endpoint and resolves its bearer token via a
# headersHelper that reads the gh keychain on demand — so no PAT is exported
# into the shell env. User scope = all projects on this machine; idempotent,
# so safe to re-run. We verify the write landed and say so plainly rather
# than trusting add-json's optimistic "Added" message.
_claude_register_github_mcp() {
  command -v claude > /dev/null 2>&1 || return 0
  command -v jq > /dev/null 2>&1 || return 0

  local helper="${HOME}/.local/bin/gh-mcp-auth-header"
  local cfg="${HOME}/.claude.json"
  local desired
  desired=$(printf '{"type":"http","url":"https://api.githubcopilot.com/mcp/","headersHelper":"%s"}' "${helper}")

  # Already registered with the right helper path → nothing to do.
  if [[ -f "${cfg}" ]] &&
    [[ "$(jq -r '.mcpServers.github.headersHelper // empty' "${cfg}" 2> /dev/null)" == "${helper}" ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 github MCP server registered (user scope, gh-keychain auth)\033[0m\n'
    return 0
  fi

  claude mcp remove github --scope user > /dev/null 2>&1 || true
  claude mcp add-json github "${desired}" --scope user > /dev/null 2>&1 || true

  if [[ -f "${cfg}" ]] &&
    [[ "$(jq -r '.mcpServers.github.headersHelper // empty' "${cfg}" 2> /dev/null)" == "${helper}" ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 github MCP server registered (user scope, gh-keychain auth)\033[0m\n'
  else
    printf '\033[0;33m  \xe2\x86\x92 github MCP server not registered — re-run "dot sync --only=claude" from a regular terminal\033[0m\n' >&2
  fi
}

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
      printf '\033[0;31m  \xe2\x9c\x97 Claude Code CLI install failed — run from a regular terminal\033[0m\n' >&2
      return 1
    fi
  fi

  _claude_register_github_mcp
}
