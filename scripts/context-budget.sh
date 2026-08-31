#!/usr/bin/env sh
# Always-loaded context budget — the single source for the ceilings.
#
# Called from lefthook's pre-commit (so the ceiling is hit at commit time, not
# after the push) and .github/workflows/lint.yml (so it holds for anything that
# arrives without a local hook). Both call sites are one line; the numbers and
# the reasoning live here, once.
#
# Usage: scripts/context-budget.sh [file...]
#   With no arguments, checks every capped file. With arguments (lefthook passes
#   staged files), checks only the capped ones among them and ignores the rest.
#   The link inventory below runs either way — it is a property of boomfile.toml,
#   not of whatever happens to be staged.
#
# WHY A CEILING: these files are symlinked into ~/.claude/ and loaded before
# every task, so every byte is billed to every request of every session —
# including the unattended ones nobody is watching. A ceiling is the only thing
# that makes a cut permanent: past this, something goes out before anything
# comes in.
#
# WHY PER-FILE: the two files have different jobs, and a ceiling set too close to
# current size stops forcing DISPLACEMENT and starts forcing THRASH — you delete
# whatever is cheapest to delete, not whatever is least worth loading. Each
# leaves roughly a fifth free: enough for a legitimate addition, not a section.
#
# WHY AN EXPLICIT LIST, NEVER A *.md GLOB: DECISIONS.md is deliberately UNCAPPED
# and unbanned. It is not symlinked into ~/.claude/, so it costs nothing per
# session, and capping the overflow destination would push content back into the
# loaded file, inverting the whole mechanism.
#
# WHY THE DATE BAN: a date makes a sentence a record rather than a rule, so it is
# the cheap proxy for the whole rotting class. No false-positive risk: a full
# YYYY-MM-DD has no business in an instruction file.
#
# WHY THE COUNT IGNORES HTML COMMENTS: Claude Code strips block-level HTML
# comments before injecting the file, so a note to a human maintainer costs ZERO
# tokens and must not compete for the ceiling. Comments inside fenced code blocks
# ARE preserved by the client, so the strip below is an approximation that does
# not model fences; the loop fails on a fence rather than quietly under-counting.
#
# WHY THE LINK INVENTORY: every `dst = "~/.claude/…"` in boomfile.toml must be
# classified below or this fails, so a new link is a decision instead of a drift.
# A comment predicting that failure did not prevent it — three links arrived with
# the budget none the wiser before this was enforced.
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
  # against a resolved path. Expanding to $HOME makes every pattern miss, and the
  # inventory then reports every link as unknown.
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
# A missing boomfile FAILS rather than skipping: an inventory that silently
# checks nothing is a gate that prints `ok` for an input it never read. Both call
# sites run from the repo root, where this file always exists.
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

# ── no prose may restate a count this repo computes ───────────────────
# WHY. An audit tested every checkable factual claim in this repo's prose and
# found all of them wrong — including three separate statements of the link
# count (README, DECISIONS.md, and a comment six lines above the line that
# PRINTS the correct one), and three different figures for the payload files
# boomfile.toml names. DECISIONS.md already publishes the rule this enforces:
# a number "may never describe how the system currently is — name the
# authority instead of the value".
#
# NOT a comment-ratio ceiling. That was considered and is the wrong
# instrument: a ratio cannot tell a hard-won mechanism explanation from a
# restated constant, so it forces deletion of whichever comment is cheapest
# rather than whichever is least worth keeping. This asserts one property
# instead — if a script here computes it, prose may not also assert it.
#
# Scoped deliberately to the two counts that actually rotted. A general
# "no digits near nouns" rule would fire on every measurement in a dated
# DECISIONS.md entry, and those are honest: the date is what makes them true.
# NO `\b`. git grep's ERE does not implement it: the pattern compiles, matches
# nothing, and the gate passes on everything — verified by injecting "14 links"
# and watching the first draft of this check report ok. Explicit character-class
# boundaries, the same idiom `guard-lib.sh` uses for its verb regex.
_B='([^A-Za-z0-9_-]|$)'
restated=$(git grep -nEI \
  "(^|[^A-Za-z0-9_-])([0-9]+|ten|eleven|twelve|(thir|four|fif|six|seven|eigh|nine)teen|twenty) (~/\.claude/ )?(links|payload files)$_B" \
  -- . ':(exclude)scripts/context-budget.sh' 2> /dev/null || true)
if [ -n "$restated" ]; then
  echo "$restated" | while IFS= read -r hit; do
    echo "context-budget: $hit"
  done
  echo "context-budget: prose restates a count a script computes — name the authority, not the value (see DECISIONS.md, \"How to write a number so it cannot rot\")"
  fail=1
else
  echo "ok no restated counts"
fi

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
  echo "  a note to a human     -> an HTML comment; the client strips it, so it is free"
  echo "  already enforced      -> nowhere. Describing a control is not the control."
  exit 1
fi
