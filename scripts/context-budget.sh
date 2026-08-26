#!/usr/bin/env sh
# Always-loaded context budget — the single source for the ceilings.
#
# Called from two places, deliberately: lefthook's pre-commit (so the ceiling is
# hit at commit time, not after the push) and .github/workflows/lint.yml (so it
# holds for anything that arrives without a local hook). Both call sites are one
# line; the numbers and the reasoning live here, once.
#
# Usage: scripts/context-budget.sh [file...]
#   With no arguments, checks every capped file. With arguments (lefthook passes
#   staged files), checks only the capped ones among them and ignores the rest.
#
# WHY A CEILING: these files are symlinked into ~/.claude/ and loaded before
# every task, so every byte is billed to every request of every session —
# including the unattended ones nobody is watching. dot-claude/CLAUDE.md went
# 348 -> 848 lines in sixteen days and 1 of 124 commits ever made it smaller, so
# a ceiling is the only thing that makes a cut permanent: past this, something
# goes out before anything comes in.
#
# WHY PER-FILE: the two files have different jobs, and a ceiling set too close to
# current size stops forcing DISPLACEMENT and starts forcing THRASH — you delete
# whatever is cheapest to delete, not whatever is least worth loading. Each
# leaves roughly a fifth free: enough for a legitimate addition, not a section.
#
# WHY AN EXPLICIT LIST, NEVER A *.md GLOB: DECISIONS.md, SETTINGS.md and
# REFERENCE.md are deliberately UNCAPPED and unbanned. They are not symlinked
# into ~/.claude/, so they cost nothing per session. Capping the overflow
# destination would push content back into the loaded file, inverting the whole
# mechanism.
#
# WHY THE DATE BAN: it is the cheap proxy for the whole rotting class. A date
# makes a sentence a record rather than a rule, and every changelog entry,
# self-correction and "measured against <version>" paragraph in the 18k-token
# predecessor carried one. No false-positive risk here: a full YYYY-MM-DD has no
# business in an instruction file.
set -eu

# The capped set. Adding a file to ~/.claude/ without adding it here is how the
# budget silently stops applying.
limit_for() {
  case "$1" in
    dot-claude/CLAUDE.md) echo 2500 ;;
    CLAUDE.md) echo 3000 ;;
    *) echo "" ;;
  esac
}

if [ "$#" -eq 0 ]; then
  set -- dot-claude/CLAUDE.md CLAUDE.md
fi

fail=0
for f in "$@"; do
  limit=$(limit_for "$f")
  [ -n "$limit" ] || continue

  n=$(wc -c < "$f" | tr -d ' ')
  if [ "$n" -gt "$limit" ]; then
    echo "$f: $n bytes, ceiling $limit (~$(((n - limit) / 4)) tokens over)"
    fail=1
  else
    echo "ok $f ($n bytes, ceiling $limit)"
  fi

  if grep -nE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f"; then
    echo "$f: dated claim(s) above — a date makes it a record, not a rule"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "An always-loaded file is charged to every request of every session."
  echo "Put it where it belongs instead:"
  echo "  a procedure           -> a skill in dot-claude/skills/"
  echo "  it must actually hold -> a hook, permissions.deny, or a boom verify check"
  echo "  a reason or history   -> dot-claude/DECISIONS.md"
  echo "  a settings.json key   -> dot-claude/SETTINGS.md"
  echo "  already enforced      -> nowhere. Describing a control is not the control."
  exit 1
fi
