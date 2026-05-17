# shellcheck shell=bash
# Claude Code CLI install. Cross-OS — the native installer handles both.

if should_run claude; then
  echo ""
  echo "==> Claude Code"
  if command -v claude &> /dev/null; then
    ok "Claude Code CLI installed ($(claude --version 2> /dev/null))"
  else
    warn "Installing Claude Code CLI (native installer)..."
    if curl -fsSL https://claude.ai/install.sh | bash; then
      ok "Claude Code CLI installed"
    else
      fail "Claude Code CLI install failed — re-run sync.sh or install manually"
    fi
  fi
fi # should_run claude
