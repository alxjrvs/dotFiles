#!/bin/bash
# What chezmoi cannot own: the Claude Code CLI and the gh extension. Claude Code itself adds the
# marketplaces settings.json declares and installs its enabled plugins, in the background of the
# first session. Every apply, so a step behind `gh auth login` converges next time.
# Every failure is reported, never fatal: a non-zero script stops every later one.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# Claude Code CLI via the native installer, which self-updates.
command -v claude > /dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash ||
  echo "provision: could not install the Claude Code CLI" >&2

# The one gh extension, owner-qualified because same-named community forks exist, pinned to the
# newest release a week old (upkeep advances it). The local list first: `gh auth status` is a
# network round trip.
if command -v gh > /dev/null 2>&1 && ! gh extension list 2> /dev/null | grep -qw github/gh-stack &&
  gh auth status > /dev/null 2>&1; then
  gh extension install github/gh-stack --pin "v$(mise latest github:github/gh-stack)" ||
    echo "provision: could not install gh-stack" >&2
fi
