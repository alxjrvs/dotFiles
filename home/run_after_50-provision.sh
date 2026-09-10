#!/bin/bash
# Every-apply provisioning: each step is idempotent and cheap when converged. No hash gate, so a
# step that has to wait for `gh auth login` on a fresh machine converges on the next apply.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:$PATH"

# Claude Code CLI via the native installer, which self-updates; never brew or npm.
command -v claude > /dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash

# node and bun. A no-op when converged; brew (script 10) installs mise itself. prune drops
# versions no config names any more, and rebuilds the shims so a retired tool cannot shadow brew's.
mise install --yes
mise prune --yes

# gh extensions, owner-qualified because same-named community forks exist.
if gh auth status > /dev/null 2>&1; then
  installed=$(gh extension list 2> /dev/null | awk '{print $3}')
  for ext in github/gh-stack dlvhdr/gh-dash meiji163/gh-notify; do
    printf '%s\n' "$installed" | grep -qx "$ext" || gh extension install "$ext"
  done
fi

# User-scoped MCP servers live only in ~/.claude.json, which nothing tracks, so they converge here.
if command -v claude > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  op_mcp=/Applications/1Password.app/Contents/MacOS/1password-mcp
  if [ -x "$op_mcp" ] && ! jq -e '.mcpServers["1password"]' "$HOME/.claude.json" > /dev/null 2>&1; then
    claude mcp add --scope user 1password -- "$op_mcp"
  fi
  # Absolute paths and /bin/sh: the desktop app spawns MCP servers with a bare environment.
  # Re-registered whenever the recorded entry differs from this one. No --exclude-tools: the
  # agent may file issues as well as comment, and GitHub's Issues permission cannot split them.
  mcp=/opt/homebrew/bin/github-mcp-server
  if [ -x "$mcp" ]; then
    cmd="GITHUB_PERSONAL_ACCESS_TOKEN=\"\$($HOME/.local/bin/op-sa read op://claude-agent/claude-git-pat/credential)\" exec $mcp stdio --toolsets context,repos,issues,pull_requests,actions"
    want=$(jq -cn --arg cmd "$cmd" '{type: "stdio", command: "/bin/sh", args: ["-c", $cmd]}')
    have=$(jq -c '.mcpServers.github // empty | {type, command, args}' "$HOME/.claude.json" 2> /dev/null || true)
    if [ "$have" != "$want" ]; then
      [ -z "$have" ] || claude mcp remove --scope user github
      claude mcp add-json --scope user github "$want"
    fi
  fi
fi

# The agent's GitHub PAT, from the vault into the login keychain on every apply, so a rotation
# in 1Password lands on the next apply. Written by git's own helper (that puts the helper on the
# item's ACL), value on stdin, `erase` then `store` (before git 2.45 store is a silent no-op on
# an existing item, and re-creating it keeps the ACL current). No service-account token yet is
# the fresh-machine case and skips quietly; a token that no longer works says so.
_helper="$(git --exec-path)/git-credential-osxkeychain"
if security find-generic-password -s op-claude-agent > /dev/null 2>&1 && [ -x "$_helper" ]; then
  if _pat=$("$HOME/.local/bin/op-sa" read op://claude-agent/claude-git-pat/credential) && [ -n "$_pat" ]; then
    printf 'protocol=https\nhost=github.com\nusername=claude-agent\n\n' | "$_helper" erase || true
    printf 'protocol=https\nhost=github.com\nusername=claude-agent\npassword=%s\n\n' "$_pat" |
      "$_helper" store || echo "provision: could not store the agent PAT; agent pushes will prompt" >&2
  else
    echo "provision: could not read the agent PAT from the vault; is the service-account token still valid?" >&2
  fi
fi
unset _pat _helper
