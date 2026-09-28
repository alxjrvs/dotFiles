#!/bin/bash
# Claude Code on the web starts without this repo's tools, and its proxy blocks mise.run and the
# GitHub API that mise resolves releases through. So mise comes from npm and the pins in mise.toml
# from PyPI and the Go proxy, which a cloud session always reaches; mise is told to leave those
# five to PATH. `mise run lint` runs there; apply-check downloads GitHub archives, so it is CI's.
# A failing SessionStart hook is reported and never blocks the session.
set -euo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = true ] || exit 0
cd "$CLAUDE_PROJECT_DIR"
export GOBIN="$HOME/.local/bin" PATH="$HOME/.local/bin:$PATH"
pin() { sed -n "s/^$1 = \"\(.*\)\"$/\1/p" mise.toml; }

command -v zsh > /dev/null || { apt-get update -q && apt-get install -y -q zsh; } > /dev/null
command -v mise > /dev/null || npm install -g --silent @jdxcode/mise
command -v shellcheck > /dev/null || uv tool install -q "shellcheck-py==$(pin shellcheck).*"
command -v zizmor > /dev/null || uv tool install -q "zizmor==$(pin zizmor)"
command -v shfmt > /dev/null || go install "mvdan.cc/sh/v3/cmd/shfmt@v$(pin shfmt)"
command -v actionlint > /dev/null || go install "github.com/rhysd/actionlint/cmd/actionlint@v$(pin actionlint)"
# chezmoi's go.mod has `exclude` directives, which `go install pkg@version` refuses; build it as
# the main module instead.
command -v chezmoi > /dev/null || (
  v=$(pin chezmoi)
  cd "$(go mod download -json "github.com/twpayne/chezmoi/v2@v$v" | jq -r .Dir)"
  go build -ldflags "-X main.version=$v" -o "$GOBIN/chezmoi" .
)
mise trust --quiet

{
  echo "export PATH=\"$HOME/.local/bin:\$PATH\""
  echo "export MISE_DISABLE_TOOLS=chezmoi,shellcheck,shfmt,actionlint,zizmor"
} >> "$CLAUDE_ENV_FILE"
