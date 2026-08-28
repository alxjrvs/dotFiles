#!/usr/bin/env sh
# Skill frontmatter description cap — the single source, and now enforced in
# BOTH places rather than only in CI.
#
# WHY IT EXISTS. Every skill's `description:` is loaded into every session so the
# model can decide whether the skill is relevant. The body is not. A description
# that grows into a summary is a permanent tax on every request, paid to explain
# a skill that may never be invoked — the same argument scripts/context-budget.sh
# makes for the two symlinked CLAUDE.md files.
#
# WHY THIS FILE EXISTS. The check lived only in .github/workflows/lint.yml, with
# no lefthook twin — the inverse of every other gate here, and the one asymmetry
# that lets a commit pass locally and fail after the push. Editing a SKILL.md
# description was the one edit whose feedback arrived a minute late instead of
# immediately.
set -eu

CAP=60
fail=0

if [ "$#" -eq 0 ]; then
  set -- dot-claude/skills/*/SKILL.md
fi

# See settings-guardrails.sh. This one already defaults to a glob when called
# with no arguments, but the glob itself can match nothing — and an explicit
# path that does not exist was silently skipped rather than reported.
[ "$#" -gt 0 ] || {
  echo "no inputs — the skills glob matched nothing, so no description was checked" >&2
  exit 1
}

for f in "$@"; do
  [ -f "$f" ] || {
    echo "$f: expected skill file is missing"
    fail=1
    continue
  }
  case "$f" in
    *SKILL.md) ;;
    *) continue ;;
  esac

  d=$(awk '/^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$f")
  if [ -z "$d" ]; then
    echo "$f: frontmatter has no description:"
    fail=1
    continue
  fi

  w=$(printf '%s' "$d" | wc -w | tr -d ' ')
  if [ "$w" -gt "$CAP" ]; then
    echo "$f: description is $w words (cap $CAP) — it loads into EVERY session"
    fail=1
  else
    echo "ok $f ($w words)"
  fi
done

[ "$fail" -eq 0 ] || exit 1
