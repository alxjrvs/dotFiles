#!/usr/bin/env bash
# gh-mcp-stdio — launch GitHub's MCP server in stdio mode for Claude DESKTOP,
# with the PAT injected from 1Password instead of stored in a config file.
#
# Why this exists at all (Claude Code does NOT use it):
#   Claude Code talks to the remote server at api.githubcopilot.com/mcp/ over
#   HTTP and authenticates with a `headersHelper` (`op-agent header`). Claude
#   Desktop has no headersHelper, and it cannot use the remote server either:
#   GitHub's remote MCP authenticates through a registered GitHub App, which
#   Desktop's "Add custom connector" OAuth flow does not support. GitHub's own
#   docs/installation-guides/install-claude.md says to run the server locally
#   for Desktop. So Desktop gets a local stdio server, and this is its launcher.
#
# Why a launcher rather than the documented config:
#   GitHub's documented Desktop config hardcodes the token —
#     "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "YOUR_GITHUB_PAT" }
#   — which would put a live classic PAT in plaintext in
#   ~/Library/Application Support/Claude/claude_desktop_config.json, a
#   world-readable-by-your-user file that the app rewrites and that no vault
#   protects. That breaks the standing rule that agent secrets live only in
#   1Password. Here the token is resolved at launch and exported into this
#   process only, so it reaches the server's env and nothing else: not the
#   config file, not argv (never `--token`, so it can't leak via `ps`), not a
#   shell that Claude can run, not a transcript.
#
# Claude Desktop execs this from a GUI context with a minimal PATH and no shell
# profile, so PATH is normalized below and the config must point at the absolute
# path /Users/<user>/.local/bin/gh-mcp-stdio.
set -euo pipefail

# GUI-launched processes inherit a bare PATH — mise shims (github-mcp-server),
# ~/.local/bin (op-agent) and homebrew (op) all have to be added explicitly.
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

PAT_REF="op://claude-agent/claude-git-pat/credential"

command -v op-agent > /dev/null 2>&1 || {
  echo "gh-mcp-stdio: op-agent not on PATH — run 'boom source'" >&2
  exit 1
}
command -v github-mcp-server > /dev/null 2>&1 || {
  echo "gh-mcp-stdio: github-mcp-server not installed — run 'mise install'" >&2
  exit 1
}

# Resolve via the service account (keychain-backed, no biometric) so this works
# when Desktop is launched at login with no unlocked 1Password app.
token="$(op-agent secret "$PAT_REF" 2> /dev/null || true)"
[[ -n "$token" ]] || {
  # Fail loudly instead of starting an unauthenticated server: Desktop would
  # otherwise show a server that connects and then 401s on every call, which is
  # exactly the silent-failure mode that hid the last GitHub MCP outage.
  echo "gh-mcp-stdio: could not resolve $PAT_REF (check 'op-agent status')" >&2
  exit 1
}

export GITHUB_PERSONAL_ACCESS_TOKEN="$token"
unset token
exec github-mcp-server stdio
