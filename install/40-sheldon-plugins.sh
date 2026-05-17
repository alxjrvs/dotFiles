# shellcheck shell=bash
# Update sheldon's plugin lockfile. Runs after symlinks so plugins.toml is
# in place. Tag is `sheldon` (same as bin check); --only=sheldon hits both.

if should_run sheldon; then
  echo ""
  echo "==> Sheldon plugins"
  warn "Updating Sheldon plugins..."
  timeout 30 sheldon lock --update || warn "Sheldon lock timed out or failed (may be offline) — skipping"
  ok "Sheldon plugins up to date"
fi # should_run sheldon