#!/bin/bash
# Every-apply provisioning: each step is idempotent and cheap when converged. No hash gate, so a
# step that has to wait for `gh auth login` on a fresh machine converges on the next apply.
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:$PATH"

# Claude Code CLI via the native installer, which self-updates; never brew or npm.
command -v claude > /dev/null 2>&1 || curl -fsSL https://claude.ai/install.sh | bash

# node and bun. A no-op when converged; brew (script 10) installs mise itself.
mise install --yes

# gh extensions, owner-qualified because same-named community forks exist.
if gh auth status > /dev/null 2>&1; then
  installed=$(gh extension list 2> /dev/null | awk '{print $3}')
  for ext in github/gh-stack dlvhdr/gh-dash meiji163/gh-notify; do
    printf '%s\n' "$installed" | grep -qx "$ext" || gh extension install "$ext"
  done
fi
