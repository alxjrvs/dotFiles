#!/usr/bin/env sh
# Brewfile drift — is this machine reproducible from the Brewfile?
#
# `brew bundle` INSTALLS what the Brewfile names. It never uninstalls what the
# Brewfile omits, so a package installed by hand stays forever, invisible, and a
# fresh machine silently does not get it. That is one-directional drift with no
# alarm, and it had run for months: 21 casks installed against 11 declared, and
# five top-level formulae undeclared.
#
# Worse than the count, the Brewfile CLAIMED otherwise. A block headed "NOT here,
# deliberately, though brew had installed them" described removals that never
# happened — the packages were still installed the whole time. A file that
# describes a state it does not enforce eventually describes a state that is not
# true, and this one did.
#
# WHAT THIS CHECKS. Only `brew leaves` (top-level formulae, not the dependency
# closure) and casks. A dependency is the business of whatever pulled it in.
#
# THE EXCLUSION LIST IS PART OF THE CONTRACT. Some packages are installed and
# deliberately NOT declared, each for a reason the Brewfile states: they are
# owned by mise, or they pull in a second copy of a runtime, or a native macOS
# path replaced them. Those must not fail this check, and they must not be
# silently forgotten either — naming them here is what makes "deliberately
# excluded" different from "nobody noticed".
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

# Installed but deliberately undeclared. Each name's full reason is in the
# Brewfile's own exclusion block; the short form:
#   gh, actionlint, osv-scanner, shellcheck  — declared in mise.toml. A brew copy
#     wins on PATH in some shells, which makes mise's pin inert. Uninstall by
#     hand: `brew uninstall <name>`.
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
#     Caps Lock remap; no kernel extension needed. Uninstall by hand.
#   zulu@17 — the same JDK as the declared `zulu17`, installed twice under two
#     cask names. Its Caskroom holds only .metadata (no version directory), so
#     it is the empty one. Uninstall by hand.
excluded_casks() {
  cat << 'X'
karabiner-elements
zulu@17
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
  echo "Either declare it in $BREWFILE (a fresh machine should get it) or add it"
  echo "to the exclusion list in this script WITH its reason (it is owned by mise,"
  echo "duplicates a runtime, or a native path replaced it). A third option —"
  echo "leaving it undeclared and unlisted — is how this drifted in the first place."
  exit 1
fi

echo "ok brew-drift ($(wc -l < "$tmp/installed-formulae" | tr -d ' ') formulae, $(wc -l < "$tmp/installed-casks" | tr -d ' ') casks)"
