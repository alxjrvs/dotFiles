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
#   The link inventory below runs either way — it is a property of boomfile.toml,
#   not of whatever happens to be staged.
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
#
# WHY THE COUNT IGNORES HTML COMMENTS: it used to bill them, and that was wrong
# in the expensive direction. Claude Code strips block-level HTML comments before
# injecting the file — "Block-level HTML comments (<!-- maintainer notes -->) in
# CLAUDE.md files are stripped before the content is injected into Claude's
# context" — so a note to a human maintainer costs ZERO tokens. Counting raw
# bytes meant those notes competed for the ceiling and got deleted to fit: the
# gate was forcing out content that was already free. Comments inside fenced code
# blocks ARE preserved by the client, so the strip below is an approximation that
# does not model fences; neither capped file contains one, and the loop below
# fails on a fence rather than quietly under-counting if that ever changes.
#
# WHY THE LINK INVENTORY: the header above used to end with "Adding a file to
# ~/.claude/ without adding it here is how the budget silently stops applying",
# and then that happened three times — skills/, agents/ and loop.md all arrived
# as links with the budget none the wiser, while README and DECISIONS went on
# saying only two files were linked at all. A comment predicting a failure does
# not prevent it. Every `dst = "~/.claude/…"` in boomfile.toml must now be
# classified below or this fails, so the next one is a decision instead of a
# drift.
set -eu

BOOMFILE=${BOOMFILE:-boomfile.toml}

# ── the capped set ────────────────────────────────────────────────────
limit_for() {
  case "$1" in
    dot-claude/CLAUDE.md) echo 2500 ;;
    CLAUDE.md) echo 3000 ;;
    *) echo "" ;;
  esac
}

# ── what every ~/.claude/ link costs a session ────────────────────────
# Adding a link to boomfile.toml means adding it here, and saying which it is.
classify_link() {
  # The tilde is LITERAL here and must stay literal: these patterns are matched
  # against the raw `dst = "~/.claude/…"` strings read out of boomfile.toml, not
  # against a resolved path. Expanding to $HOME would make every pattern miss —
  # which is the bug this had before the quotes went on, when the inventory
  # reported all fourteen links as unknown.
  # shellcheck disable=SC2088
  case "$1" in
    "~/.claude/CLAUDE.md") echo "billed in full — capped above" ;;
    "~/.claude/settings.json") echo "config, not context — costs nothing" ;;
    "~/.claude/hooks/"*) echo "executed, never read into context" ;;
    "~/.claude/loop.md") echo "read on demand by /loop" ;;
    "~/.claude/skills/") echo "descriptions billed — capped by description-cap.sh" ;;
    "~/.claude/agents/") echo "descriptions billed — capped by description-cap.sh" ;;
    "~/.claude/rules/") echo "path-scoped — free until a matching file is read; gated by rules-scoped.sh" ;;
    *) echo "" ;;
  esac
}

# Strip block-level HTML comments. See the header: the client does this before
# billing, so the ceiling must too.
strip_comments() {
  awk '
    {
      line = $0
      while (1) {
        if (incmt) {
          i = index(line, "-->")
          if (i == 0) { line = ""; break }
          line = substr(line, i + 3); incmt = 0
        } else {
          i = index(line, "<!--")
          if (i == 0) break
          rest = substr(line, i + 4)
          j = index(rest, "-->")
          if (j == 0) { line = substr(line, 1, i - 1); incmt = 1; break }
          line = substr(line, 1, i - 1) substr(rest, j + 3)
        }
      }
      print line
    }
  ' "$1"
}

fail=0

# ── link inventory ────────────────────────────────────────────────────
# A missing boomfile FAILS rather than skipping. scripts/tests/gates.sh exists
# because three gates here once printed `ok` for an input they never read, and
# an inventory that silently checks nothing is that same bug: both call sites
# run from the repo root, where this file always exists.
[ -f "$BOOMFILE" ] || {
  echo "context-budget: no $BOOMFILE — the link inventory checked nothing" >&2
  exit 1
}

links=$(sed -n 's/^dst = "\(~\/\.claude\/[^"]*\)".*/\1/p' "$BOOMFILE" | sort -u)
[ -n "$links" ] || {
  echo "context-budget: $BOOMFILE declares no ~/.claude/ links — that cannot be right" >&2
  exit 1
}

n_links=0
for l in $links; do
  n_links=$((n_links + 1))
  if [ -z "$(classify_link "$l")" ]; then
    echo "context-budget: $BOOMFILE links $l, and this script does not know what it costs"
    fail=1
  fi
done
[ "$fail" -ne 0 ] || echo "ok link inventory ($n_links ~/.claude/ links, all classified)"

# ── per-file ceilings ─────────────────────────────────────────────────
if [ "$#" -eq 0 ]; then
  set -- dot-claude/CLAUDE.md CLAUDE.md
fi

for f in "$@"; do
  limit=$(limit_for "$f")
  [ -n "$limit" ] || continue

  # A fenced block would make the comment strip below under-count, because the
  # client preserves comments inside fences. Fail loudly rather than silently.
  if grep -q '```' "$f"; then
    echo "$f: contains a fenced code block — the HTML-comment strip does not model fences"
    fail=1
  fi

  raw=$(wc -c < "$f" | tr -d ' ')
  n=$(strip_comments "$f" | wc -c | tr -d ' ')
  free=$((raw - n))

  if [ "$n" -gt "$limit" ]; then
    echo "$f: $n billed bytes, ceiling $limit (~$(((n - limit) / 4)) tokens over)"
    fail=1
  elif [ "$free" -gt 0 ]; then
    echo "ok $f ($n billed bytes of $raw, ceiling $limit; $free in HTML comments, free)"
  else
    echo "ok $f ($n bytes, ceiling $limit)"
  fi

  if strip_comments "$f" | grep -nE '[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
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
  echo "  a note to a human     -> an HTML comment; the client strips it, so it is free"
  echo "  already enforced      -> nowhere. Describing a control is not the control."
  exit 1
fi
