# shellcheck shell=bash
# Darwin: fzf shell integration. The brew-shipped install script is the
# canonical wiring path; runs idempotent on repeat invocation.

[ "$OS" = "Darwin" ] || return 0

if should_run fzf; then
  echo ""
  echo "==> fzf"
  warn "Installing/updating fzf shell integration..."
  "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
  ok "fzf shell integration up to date"
fi # should_run fzf