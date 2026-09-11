#!/bin/bash
# Every-apply provisioning, run before files land: `claude plugin install` rewrites
# ~/.claude/settings.json in its own key order, so it goes first and chezmoi's copy lands last.
# Each step is idempotent and cheap when converged. No hash gate, so a step that has to wait for
# `gh auth login` or brew's first bundle on a fresh machine converges on the next apply. Every
# tool is guarded: a host without brew skips what brew would have installed. Installed-but-
# undeclared items are reported, never removed; that is a judgement, not a converge.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:$PATH"
# The declared state, present before ~/.claude is.
settings="$CHEZMOI_SOURCE_DIR/dot_claude/settings.json"

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
  want=$'github/gh-stack\ndlvhdr/gh-dash\nmeiji163/gh-notify'
  have=$(gh extension list 2> /dev/null | awk '{print $3}')
  for ext in $want; do
    printf '%s\n' "$have" | grep -qx "$ext" || gh extension install "$ext"
  done
  for ext in $have; do
    printf '%s\n' "$want" | grep -qx "$ext" || echo "provision: undeclared gh extension $ext" >&2
  done
fi

if command -v claude > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  # Plugins declared in settings.json: declaring one does not install it.
  declared=$(jq -r '.enabledPlugins | keys[]' "$settings")
  want=$(jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' "$settings")
  have=$(claude plugin list --json 2> /dev/null | jq -r '.[] | select(.scope == "user") | .id' | sort -u || true)
  for plugin in $want; do
    printf '%s\n' "$have" | grep -qx "$plugin" ||
      claude plugin install "$plugin" || echo "provision: could not install $plugin" >&2
  done
  for plugin in $have; do
    printf '%s\n' "$declared" | grep -qx "$plugin" || echo "provision: undeclared plugin $plugin" >&2
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
