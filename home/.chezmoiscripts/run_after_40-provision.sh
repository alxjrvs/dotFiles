#!/bin/bash
# What chezmoi cannot own: the Claude Code CLI, the gh extension, and the marketplaces and
# plugins settings.json declares. Every apply, so a step behind `gh auth login` converges next time.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
# Marketplace and plugin `owner/repo` sources clone over SSH by default; HTTPS needs no agent.
export CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1

# Claude Code CLI via the native installer, which self-updates. Reported, not fatal: a non-zero
# script stops every later one, and the apps and the Caps Lock remap come after this.
command -v claude > /dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash ||
  echo "provision: could not install the Claude Code CLI" >&2

# The one gh extension, owner-qualified because same-named community forks exist.
if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
  gh extension list 2> /dev/null | awk '{print $3}' | grep -qx github/gh-stack ||
    gh extension install github/gh-stack || echo "provision: could not install gh-stack" >&2
fi

if command -v claude > /dev/null 2>&1 && command -v jq > /dev/null 2>&1; then
  settings="$HOME/.claude/settings.json"
  missing=""
  # Marketplaces first: the official one is registered by the first interactive launch, which a
  # fresh machine has not had, and a declared one is known but not added until something adds it.
  have=$(claude plugin marketplace list 2> /dev/null || true)
  for repo in anthropics/claude-plugins-official $(jq -r '.extraKnownMarketplaces[].source.repo' "$settings"); do
    printf '%s\n' "$have" | grep -qF "($repo)" ||
      claude plugin marketplace add "$repo" || missing="$missing $repo"
  done
  have=$(claude plugin list --json 2> /dev/null | jq -r '.[] | select(.scope == "user") | .id' || true)
  for plugin in $(jq -r '.enabledPlugins | to_entries[] | select(.value) | .key' "$settings"); do
    # The JSON result's last line is what tells a `failed` install from an `ok` one.
    printf '%s\n' "$have" | grep -qx "$plugin" ||
      claude plugin install "$plugin" --json | tail -1 | jq -e '.outcome == "ok"' > /dev/null ||
      missing="$missing $plugin"
  done
  # Reported, never fatal. #412 put the apps and the Caps Lock remap after this script so a
  # stoppage leaves a usable shell; exiting non-zero here would stop exactly those. The next
  # apply retries whatever is still named, so a step behind `gh auth login` converges.
  if [ -n "$missing" ]; then
    echo "provision: not installed:$missing" >&2
  fi
fi
