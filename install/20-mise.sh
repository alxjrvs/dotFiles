# shellcheck shell=bash
# Darwin: install/update tools from mise.toml.

[ "$OS" = "Darwin" ] || return 0

if should_run mise; then
  echo ""
  echo "==> mise tools"
  warn "Installing/updating tools from mise.toml..."
  mise trust ~/.config/mise/config.toml 2> /dev/null || true
  mise install
  ok "mise tools up to date"
fi # should_run mise