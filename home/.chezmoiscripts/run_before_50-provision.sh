#!/bin/bash
# Every-apply provisioning of what chezmoi cannot own. No hash gate: a step waiting on `gh auth
# login` on a fresh machine converges on the next apply. Idempotent and cheap when converged;
# every tool is guarded.
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
settings="$CHEZMOI_SOURCE_DIR/.chezmoitemplates/claude-settings.json"

# Claude Code CLI via the native installer, which self-updates; never brew or npm.
command -v claude > /dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash

# gh extensions, owner-qualified because same-named community forks exist.
if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
  for ext in github/gh-stack dlvhdr/gh-dash meiji163/gh-notify; do
    gh extension list 2> /dev/null | awk '{print $3}' | grep -qx "$ext" || gh extension install "$ext"
  done
fi

if command -v claude > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  # Plugins declared in settings.json: declaring one does not install it.
  have=$(claude plugin list --json 2> /dev/null | jq -r '.[] | select(.scope == "user") | .id' || true)
  for plugin in $(jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' "$settings"); do
    printf '%s\n' "$have" | grep -qx "$plugin" ||
      claude plugin install "$plugin" || echo "provision: could not install $plugin" >&2
  done

  # User-scoped MCP servers live only in ~/.claude.json, which nothing tracks. Absolute path: the
  # desktop app does not always hand spawned servers the login PATH.
  op_mcp=/Applications/1Password.app/Contents/MacOS/1password-mcp
  if [ -x "$op_mcp" ] && ! claude mcp get 1password > /dev/null 2>&1; then
    claude mcp add --scope user 1password -- "$op_mcp"
  fi
  # Migration: delete this line once every machine has applied it.
  claude mcp remove --scope user github > /dev/null 2>&1 || true
fi
