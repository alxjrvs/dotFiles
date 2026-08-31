#!/usr/bin/env sh
# Every `src` the boomfile links actually exists in this repo.
#
# WHY. `boomfile.toml` names the payload files by path, and a path that no longer
# exists is a `boom source` that fails partway through on a real machine, after
# it has already changed things. `taplo` proves the file PARSES, which says
# nothing about whether what it names is there.
#
# Cheap, hermetic, no network, no brew, no boom — so it runs in the ordinary lint
# job rather than waiting for the macOS one.
#
# Glob sources (`dot-claude/skills/*`, `zsh/[0-9]*.zsh`) are checked by expansion:
# a glob matching nothing is the same failure with a different spelling.
#
# Usage: scripts/boomfile-sources.sh [boomfile.toml]
set -eu

FILE=${1:-boomfile.toml}

[ -f "$FILE" ] || {
  echo "boomfile-sources: no $FILE — nothing was checked" >&2
  exit 1
}

srcs=$(sed -n 's/^src = "\([^"]*\)".*/\1/p' "$FILE")

[ -n "$srcs" ] || {
  echo "boomfile-sources: $FILE declares no src — that cannot be right" >&2
  exit 1
}

fail=0
n=0

for s in $srcs; do
  n=$((n + 1))
  case "$s" in
    *[*?[]*)
      # A glob: expand it and require at least one match.
      # shellcheck disable=SC2086
      set -- $s
      if [ -e "$1" ]; then
        continue
      fi
      echo "$FILE: src glob matches nothing: $s"
      fail=1
      ;;
    *)
      [ -e "$s" ] && continue
      echo "$FILE: src does not exist: $s"
      fail=1
      ;;
  esac
done

[ "$fail" -eq 0 ] || {
  echo ""
  echo "A boomfile src that is not there fails 'boom source' partway through, on a"
  echo "real machine, after it has already changed things. Fix the path or drop the link."
  exit 1
}

echo "ok boomfile sources ($n declared, all present)"
