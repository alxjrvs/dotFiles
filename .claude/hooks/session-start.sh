#!/bin/bash
# Claude Code on the web starts without this repo's tools, and its proxy blocks mise.run and the
# GitHub API that mise resolves releases through. So mise comes from npm and the pins in mise.toml
# from PyPI and the Go proxy, which a cloud session always reaches; mise is told to leave those
# five to PATH. `mise run lint` and `mise run apply-check` both run there.
# A failing SessionStart hook is reported and never blocks the session.
set -euo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = true ] || exit 0
cd "$CLAUDE_PROJECT_DIR"
export GOBIN="$HOME/.local/bin" PATH="$HOME/.local/bin:$PATH"
pin() { sed -n "s/^$1 = \"\(.*\)\"$/\1/p" mise.toml; }
# Present at the pinned version: a bump re-installs, rather than keep the binary it replaced.
has() { "$1" --version 2>&1 | grep -qF "$(pin "$1")"; }

command -v zsh > /dev/null || { apt-get update -q && apt-get install -y -q zsh; } > /dev/null
# A week-old mise, the cooldown everything else keeps (the VM is Ubuntu, so GNU date).
command -v mise > /dev/null || npm install -g --silent --before "$(date -u -d '7 days ago' +%FT%TZ)" @jdxcode/mise
has shellcheck || uv tool install -q --force "shellcheck-py==$(pin shellcheck).*"
has zizmor || uv tool install -q --force "zizmor==$(pin zizmor)"
has shfmt || go install "mvdan.cc/sh/v3/cmd/shfmt@v$(pin shfmt)"
has actionlint || go install "github.com/rhysd/actionlint/cmd/actionlint@v$(pin actionlint)"
# chezmoi's go.mod has `exclude` directives, which `go install pkg@version` refuses, so it builds
# as the main module. Only apply-check needs it, so it builds in the background (a minute); an `||`
# in place of the `if` would keep the hook's stdout open, and the session would wait for it.
if ! has chezmoi; then
  (
    v=$(pin chezmoi)
    cd "$(go mod download -json "github.com/twpayne/chezmoi/v2@v$v" | jq -r .Dir)"
    go build -ldflags "-X main.version=$v" -o "$GOBIN/chezmoi" .
  ) > /dev/null 2>&1 &
fi
mise trust --quiet

{
  echo "export PATH=\"$HOME/.local/bin:\$PATH\""
  echo "export MISE_DISABLE_TOOLS=chezmoi,shellcheck,shfmt,actionlint,zizmor"
} >> "$CLAUDE_ENV_FILE"
