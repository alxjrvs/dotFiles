#!/bin/bash
# Claude Code on the web starts without this repo's tools; install them so `mise run lint` and
# `mise run apply-check` work there too. A Mac already has mise. Needs the environment's network
# access to reach mise.run and GitHub release downloads; without it, says so and carries on.
set -euo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = true ] || exit 0
export PATH="$HOME/.local/bin:$PATH"

# errexit is off inside a function called from `if`, so every step chains explicitly.
install_tools() {
  command -v zsh > /dev/null || { apt-get update -q && apt-get install -y -q zsh; } > /dev/null || return
  command -v mise > /dev/null || { curl -fsSL https://mise.run | sh; } || return
  cd "$CLAUDE_PROJECT_DIR" && mise trust --quiet && mise install --yes
}
if ! install_tools; then
  echo "session-start: could not install this repo's tools; CI still runs every check" >&2
  exit 0
fi
echo "export PATH=\"$HOME/.local/share/mise/shims:$HOME/.local/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
