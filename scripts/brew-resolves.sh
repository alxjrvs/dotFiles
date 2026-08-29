#!/usr/bin/env sh
# Every name the Brewfile declares still resolves to a real formula or cask.
#
# WHY, AND WHY IT NEEDS A macOS RUNNER. `zulu17` was RETIRED upstream and stopped
# resolving — "Cask 'zulu17' is unavailable" — which failed `brew bundle`
# outright on a fresh machine. The Brewfile now says `zulu@17` and carries a
# comment explaining the rename, but nothing checks the next one. Homebrew
# retires and renames casks continuously; the declaration here is a claim about
# an upstream that moves without telling anyone.
#
# This is the class of failure that is INVISIBLE to the rest of the gate by
# construction: every other check reads files, and a file that names a cask which
# no longer exists is perfectly well-formed. It only surfaces where brew itself
# can answer, which is macOS — and both workflows ran ubuntu-latest only, so the
# entire setup path this repo documents was executed by nothing.
#
# ONE `brew info` CALL for everything. Per-name calls are ~35 network round trips
# and the runner is not free; `--json=v2` takes the whole list at once and reports
# what it could not find on stderr with a nonzero exit.
#
# Usage: scripts/brew-resolves.sh [Brewfile]
set -eu

FILE=${1:-Brewfile}

[ -f "$FILE" ] || {
  echo "brew-resolves: no $FILE — nothing was checked" >&2
  exit 1
}

command -v brew > /dev/null 2>&1 || {
  echo "brew-resolves: brew not on PATH — this check needs a macOS runner" >&2
  exit 1
}

# `brew "name"` / `cask "name"`, ignoring comments. The quotes are part of the
# DSL, so the extraction is exact rather than a loose word match.
formulae=$(sed -n 's/^[[:space:]]*brew[[:space:]]*"\([^"]*\)".*/\1/p' "$FILE" | sort -u)
casks=$(sed -n 's/^[[:space:]]*cask[[:space:]]*"\([^"]*\)".*/\1/p' "$FILE" | sort -u)

[ -n "$formulae" ] || [ -n "$casks" ] || {
  echo "brew-resolves: $FILE declares neither a formula nor a cask — that cannot be right" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0

if [ -n "$formulae" ]; then
  # shellcheck disable=SC2086
  if brew info --formula --json=v2 $formulae > /dev/null 2> "$tmp/formula-err"; then
    echo "ok formulae ($(printf '%s\n' "$formulae" | wc -l | tr -d ' ') declared, all resolve)"
  else
    echo "a declared formula no longer resolves:"
    cat "$tmp/formula-err" >&2
    fail=1
  fi
fi

if [ -n "$casks" ]; then
  # shellcheck disable=SC2086
  if brew info --cask --json=v2 $casks > /dev/null 2> "$tmp/cask-err"; then
    echo "ok casks ($(printf '%s\n' "$casks" | wc -l | tr -d ' ') declared, all resolve)"
  else
    echo "a declared cask no longer resolves:"
    cat "$tmp/cask-err" >&2
    fail=1
  fi
fi

[ "$fail" -eq 0 ] || {
  echo ""
  echo "A retired or renamed name fails 'brew bundle' outright on a fresh machine."
  echo "Find the new spelling with 'brew search <name>' and update the Brewfile;"
  echo "if it is gone for good, delete the line and say so in the comment block."
  exit 1
}
