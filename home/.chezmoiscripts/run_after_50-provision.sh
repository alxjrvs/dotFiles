#!/bin/bash
# Every-apply provisioning: each step is idempotent and cheap when converged. No hash gate, so a
# step that has to wait for `gh auth login` on a fresh machine converges on the next apply.
# Every tool is guarded: a Linux host without brew skips what brew would have installed.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:$PATH"

# Claude Code CLI via the native installer, which self-updates; never brew or npm.
command -v claude > /dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash

# node and bun. prune drops versions no config names any more, and rebuilds the shims so a
# retired tool cannot shadow brew's.
if command -v mise > /dev/null 2>&1; then
  mise install --yes
  mise prune --yes
fi

# gh extensions, owner-qualified because same-named community forks exist.
if gh auth status > /dev/null 2>&1; then
  installed=$(gh extension list 2> /dev/null | awk '{print $3}')
  for ext in github/gh-stack dlvhdr/gh-dash meiji163/gh-notify; do
    printf '%s\n' "$installed" | grep -qx "$ext" || gh extension install "$ext"
  done
fi

if command -v claude > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  # Plugins declared in ~/.claude/settings.json: declaring one does not install it.
  installed=$(claude plugin list --json 2> /dev/null | jq -r '.[].id' || true)
  for plugin in $(jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' "$HOME/.claude/settings.json"); do
    printf '%s\n' "$installed" | grep -qx "$plugin" ||
      claude plugin install "$plugin" || echo "provision: could not install $plugin" >&2
  done

  # User-scoped MCP servers live only in ~/.claude.json, which nothing tracks, so they converge
  # here. Absolute paths: the desktop app does not always hand spawned servers the login PATH.
  op_mcp=/Applications/1Password.app/Contents/MacOS/1password-mcp
  if [ -x "$op_mcp" ] && ! jq -e '.mcpServers["1password"]' "$HOME/.claude.json" > /dev/null 2>&1; then
    claude mcp add --scope user 1password -- "$op_mcp"
  fi
  # GitHub on gh's own token: one identity for the human, the agent and the MCP. Re-registered
  # whenever the recorded entry differs from this one.
  mcp=$(command -v github-mcp-server || true)
  gh_bin=$(command -v gh || true)
  if [ -n "$mcp" ] && [ -n "$gh_bin" ]; then
    cmd="GITHUB_PERSONAL_ACCESS_TOKEN=\"\$($gh_bin auth token)\" exec $mcp stdio --toolsets context,repos,issues,pull_requests,actions"
    want=$(jq -cn --arg cmd "$cmd" '{type: "stdio", command: "/bin/sh", args: ["-c", $cmd]}')
    have=$(jq -c '.mcpServers.github // empty | {type, command, args}' "$HOME/.claude.json" 2> /dev/null || true)
    if [ "$have" != "$want" ]; then
      [ -z "$have" ] || claude mcp remove --scope user github
      claude mcp add-json --scope user github "$want"
    fi
  fi
fi
