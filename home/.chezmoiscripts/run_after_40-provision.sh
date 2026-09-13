#!/bin/bash
# What chezmoi cannot own: the Claude Code CLI, the gh extension, and the marketplaces and
# plugins settings.json declares. Every apply, so a step behind `gh auth login` converges next time.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# Claude Code CLI via the native installer, which self-updates.
command -v claude > /dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash

# The one gh extension, owner-qualified because same-named community forks exist.
if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
  gh extension list 2> /dev/null | awk '{print $3}' | grep -qx github/gh-stack || gh extension install github/gh-stack
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
fi
