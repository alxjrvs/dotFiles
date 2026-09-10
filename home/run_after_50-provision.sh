#!/bin/bash
# Every-apply provisioning. Each step is idempotent and cheap when converged, so there is no
# hash gate: an `onchange` script that exited early would record its hash and never retry, and
# gh extensions before `gh auth login` is exactly that case on a fresh machine.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:$PATH"

# Claude Code CLI via the native installer, which self-updates; never brew or npm.
command -v claude > /dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash

# Every pinned CLI. A no-op when converged; brew (script 10) installs mise itself.
mise install --yes

# gh extensions, owner-qualified because same-named community forks exist. Needs an
# authenticated gh, which on a fresh machine comes after the first apply: skip, converge next time.
if gh auth status > /dev/null 2>&1; then
  installed=$(gh extension list 2> /dev/null | awk '{print $3}')
  for ext in github/gh-stack dlvhdr/gh-dash meiji163/gh-notify; do
    printf '%s\n' "$installed" | grep -qx "$ext" || gh extension install "$ext"
  done
fi

# User-scoped MCP servers live only in ~/.claude.json, which nothing tracks (the desktop app's
# Code tab reads the same file), so a fresh machine has none until this converges them.
if command -v claude > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  # 1Password Environments: a stdio server inside the desktop app; human approval per call.
  op_mcp=/Applications/1Password.app/Contents/MacOS/1password-mcp
  if [ -x "$op_mcp" ] && ! jq -e '.mcpServers["1password"]' "$HOME/.claude.json" > /dev/null 2>&1; then
    claude mcp add --scope user 1password -- "$op_mcp"
  fi
  # GitHub's stdio server, running as the AGENT PAT through op-sa. Absolute paths and /bin/sh
  # because the desktop app spawns MCP servers with a bare environment. Re-registers whenever
  # the recorded entry differs from this one.
  shims="$HOME/.local/share/mise/shims"
  if "$shims/github-mcp-server" --version > /dev/null 2>&1; then
    cmd="GITHUB_PERSONAL_ACCESS_TOKEN=\"\$($HOME/.local/bin/op-sa read op://claude-agent/claude-git-pat/credential)\" exec $shims/github-mcp-server stdio --toolsets context,repos,issues,pull_requests,actions"
    want=$(jq -cn --arg cmd "$cmd" '{type: "stdio", command: "/bin/sh", args: ["-c", $cmd]}')
    have=$(jq -c '.mcpServers.github // empty | {type, command, args}' "$HOME/.claude.json" 2> /dev/null || true)
    if [ "$have" != "$want" ]; then
      [ -z "$have" ] || claude mcp remove --scope user github
      claude mcp add-json --scope user github "$want"
    fi
  fi
fi
