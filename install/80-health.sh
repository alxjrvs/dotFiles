# shellcheck shell=bash
# Health checks: verify the basics after install. Cross-OS.

if should_run health; then
  echo ""
  echo "==> Health checks"

  # Git config
  if git config user.name &> /dev/null && git config user.email &> /dev/null; then
    ok "git: user.name and user.email configured"
  else
    fail "git: missing user.name or user.email — check .gitconfig"
  fi

  if [ "$OS" = "Darwin" ]; then
    # Node
    if command -v node &> /dev/null; then
      ok "node: $(node --version)"
    else
      fail "node: not found"
    fi

    # Bun
    if command -v bun &> /dev/null; then
      ok "bun: $(bun --version)"
    else
      fail "bun: not found"
    fi
  fi # Darwin
fi # should_run health