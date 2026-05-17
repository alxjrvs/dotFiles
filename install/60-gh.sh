# shellcheck shell=bash
# GitHub CLI: verify auth + install extensions. Cross-OS.

if should_run gh; then
  echo ""
  echo "==> GitHub CLI"
  if gh auth status &> /dev/null; then
    ok "gh authenticated"
    # gh extensions: each entry is "owner/repo:short-name".
    for ext_entry in \
      "dlvhdr/gh-dash:gh-dash" \
      "meiji163/gh-notify:gh-notify" \
      "actions/gh-actions-cache:gh-actions-cache"; do
      ext_repo="${ext_entry%%:*}"
      ext_name="${ext_entry##*:}"
      if gh extension list 2> /dev/null | grep -q "$ext_repo"; then
        dim "$ext_name extension already installed"
      else
        warn "Installing $ext_name extension..."
        if gh extension install "$ext_repo"; then
          ok "$ext_name installed"
        else
          warn "$ext_name install failed"
        fi
      fi
    done
  else
    warn "Not authenticated — run: gh auth login"
  fi
fi # should_run gh