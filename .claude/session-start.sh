#!/bin/bash
# Claude Code on the web starts without this repo's tools; install them so `mise run lint` and
# `mise run apply-check` work there too. Needs the environment's network access to mise.run,
# api.github.com and GitHub downloads. A failing SessionStart hook is reported and never blocks
# the session.
set -euo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = true ] || exit 0
export PATH="$HOME/.local/bin:$PATH"
command -v zsh > /dev/null || { apt-get update -q && apt-get install -y -q zsh; } > /dev/null
command -v mise > /dev/null || curl -fsSL https://mise.run | sh
cd "$CLAUDE_PROJECT_DIR"
mise trust --quiet
mise install --yes
echo "export PATH=\"$HOME/.local/share/mise/shims:$HOME/.local/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
