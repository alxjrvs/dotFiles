#!/usr/bin/env sh
# Brewfile drift — is this machine reproducible from the Brewfile?
#
# `brew bundle` INSTALLS what the Brewfile names. It never uninstalls what the
# Brewfile omits, so a package installed by hand stays forever, invisible, and a
# fresh machine silently does not get it — one-directional drift with no alarm.
#
# WHAT THIS CHECKS. Only `brew leaves` (top-level formulae, not the dependency
# closure) and casks. A dependency is the business of whatever pulled it in.
#
# THE EXCLUSION LIST IS PART OF THE CONTRACT. Some packages are installed and
# deliberately NOT declared, each for a reason: owned by mise, a second copy of a
# runtime, or replaced by a native macOS path. Naming them here is what makes
# "deliberately excluded" different from "nobody noticed".
set -eu

BREWFILE=${1:-Brewfile}
[ -f "$BREWFILE" ] || {
  echo "brew-drift: no Brewfile at $BREWFILE" >&2
  exit 2
}

command -v brew > /dev/null 2>&1 || {
  echo "ok brew-drift (brew not installed; nothing to compare)"
  exit 0
}

# Installed but deliberately undeclared. Full reasons: the Brewfile's own
# exclusion block. The short form:
#   gh, actionlint, osv-scanner, shellcheck — declared in mise.toml; a brew copy
#                   wins on PATH in some shells, making mise's pin inert.
#   node          — arrives only as a netlify-cli dependency; a second node is
#                   the exact hazard the mise pin exists to prevent.
#   netlify-cli   — deploys use a version-pinned `bunx netlify-cli@<ver>`.
#   heroku        — mise's `npm:heroku`; the brew tap needs an interactive
#                   `brew trust`, which stops a fresh machine halfway.
#   usage         — a mise internal dependency, not a tool this repo chose.
excluded_formulae() {
  cat << 'X'
gh
node
shellcheck
netlify-cli
heroku
usage
actionlint
osv-scanner
X
}

#   karabiner-elements — replaced by the hidutil LaunchAgent for the single
#                   Caps Lock remap; no kernel extension needed.
#   zulu17        — the RETIRED upstream name for the declared `zulu@17`. It no
#                   longer resolves as a cask, so it can only be a leftover.
excluded_casks() {
  cat << 'X'
karabiner-elements
zulu17
X
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

grep -oE '^brew "[^"]+"' "$BREWFILE" | sed 's/brew "//;s/"//' | sort -u > "$tmp/declared-formulae"
grep -oE '^cask "[^"]+"' "$BREWFILE" | sed 's/cask "//;s/"//' | sort -u > "$tmp/declared-casks"
excluded_formulae | sort -u > "$tmp/excluded-formulae"
excluded_casks | sort -u > "$tmp/excluded-casks"
sort -u "$tmp/declared-formulae" "$tmp/excluded-formulae" > "$tmp/ok-formulae"
sort -u "$tmp/declared-casks" "$tmp/excluded-casks" > "$tmp/ok-casks"

brew leaves | sort -u > "$tmp/installed-formulae"
brew list --cask 2> /dev/null | sort -u > "$tmp/installed-casks"

fail=0

# ── the check the exclusion list was standing in for ──────────────────
# A tool declared in mise.toml AND installed by brew is not "excluded", it is a
# DOUBLE INSTALL — two copies, and whichever sits earlier on PATH wins. The
# Brewfile documents eight of these ("brew's wins on PATH in some shells, so
# mise's pin is inert there") and every one of them is in excluded_formulae()
# below, so this script could never fail on the exact state it describes. That
# made the exclusion list a permanent amnesty rather than a scope note.
#
# So the overlap is now its own assertion, ahead of the drift check and NOT
# subject to the exclusions: mise owns these names, and brew having them too is
# the finding. `brew leaves` (not `brew list`) so a formula pulled in only as
# somebody else's dependency does not read as a deliberate install.
if [ -f mise.toml ] && command -v brew > /dev/null 2>&1; then
  # Both spellings mise accepts: a bare `gh = "latest"`, and a quoted, backend-
  # prefixed `"npm:heroku" = "latest"` / `"aqua:dbrgn/tealdeer" = "latest"`. The
  # brew name to compare against is the LAST path segment after the backend
  # prefix, which is what lands on PATH — reading only the bare form missed
  # heroku, netlify-cli and usage, three of the eight the Brewfile documents.
  mise_tools=$(sed -n '/^\[tools\]/,/^\[/p' mise.toml |
    sed -n 's/^"\{0,1\}\([a-zA-Z0-9_.:/-]*\)"\{0,1\}[[:space:]]*=.*/\1/p' |
    sed 's/.*[:/]//' | grep -v '^$' | sort -u)
  if [ -n "$mise_tools" ]; then
    both=$(printf '%s\n' "$mise_tools" | sort -u > "$tmp/mise-tools" && brew leaves | sort -u > "$tmp/leaves-for-mise" && comm -12 "$tmp/mise-tools" "$tmp/leaves-for-mise")
    if [ -n "$both" ]; then
      echo "declared in mise.toml AND installed by brew — two copies, PATH order decides which runs:"
      echo "$both" | sed 's/^/  /'
      echo "  -> brew uninstall $(echo "$both" | tr '\n' ' ')"
      fail=1
    else
      echo "ok no mise/brew double installs"
    fi
  fi
fi

extra_f=$(comm -23 "$tmp/installed-formulae" "$tmp/ok-formulae")
if [ -n "$extra_f" ]; then
  echo "installed, but neither declared nor listed as a deliberate exclusion:"
  echo "$extra_f" | sed 's/^/  brew /'
  fail=1
fi

extra_c=$(comm -23 "$tmp/installed-casks" "$tmp/ok-casks")
if [ -n "$extra_c" ]; then
  echo "installed casks, but neither declared nor a deliberate exclusion:"
  echo "$extra_c" | sed 's/^/  cask /'
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Three remedies, and the right one depends on whether you still use it:"
  echo "  * still use it     -> declare it in $BREWFILE, so a fresh machine gets it"
  echo "  * do not use it    -> brew uninstall it. \`brew bundle\` NEVER removes what the"
  echo "                        Brewfile omits, so undeclaring is only half of deleting."
  echo "  * owned elsewhere  -> add it to the exclusion list in this script WITH its reason"
  echo "                        (owned by mise, duplicates a runtime, replaced by a native path)."
  echo "A fourth option — leaving it undeclared and unlisted — is how this drifted in the"
  echo "first place."
  exit 1
fi

echo "ok brew-drift ($(wc -l < "$tmp/installed-formulae" | tr -d ' ') formulae, $(wc -l < "$tmp/installed-casks" | tr -d ' ') casks)"
