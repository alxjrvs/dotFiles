#!/bin/bash
# Every-apply provisioning of what chezmoi cannot own: the Claude Code CLI, gh extensions, and
# the marketplaces and plugins ~/.claude/settings.json declares (declaring one does not install
# it). No hash gate: a step waiting on `gh auth login` on a fresh machine converges on the next
# apply. Idempotent and cheap when converged; every tool is guarded.
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

# Claude Code CLI via the native installer, which self-updates.
command -v claude > /dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash

# gh extensions, owner-qualified because same-named community forks exist.
if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
  for ext in github/gh-stack dlvhdr/gh-dash meiji163/gh-notify; do
    gh extension list 2> /dev/null | awk '{print $3}' | grep -qx "$ext" || gh extension install "$ext"
  done
fi

if command -v claude > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  settings="$HOME/.claude/settings.json"
  # Marketplaces first: the official one is registered by the first interactive launch, which a
  # fresh machine has not had, and a declared one is known but not added until something adds it.
  have=$(claude plugin marketplace list 2> /dev/null || true)
  for repo in anthropics/claude-plugins-official $(jq -r '.extraKnownMarketplaces[].source.repo' "$settings"); do
    printf '%s\n' "$have" | grep -qF "($repo)" ||
      claude plugin marketplace add "$repo" || echo "provision: could not add $repo" >&2
  done
  have=$(claude plugin list --json 2> /dev/null | jq -r '.[] | select(.scope == "user") | .id' || true)
  for plugin in $(jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' "$settings"); do
    printf '%s\n' "$have" | grep -qx "$plugin" ||
      claude plugin install "$plugin" || echo "provision: could not install $plugin" >&2
  done
  # Migrations: dated, and deleted after 60 days whether or not every machine has applied them.
  claude mcp remove --scope user github > /dev/null 2>&1 || true    # #351 2026-09-10
  claude mcp remove --scope user 1password > /dev/null 2>&1 || true # #368 2026-09-12
fi
