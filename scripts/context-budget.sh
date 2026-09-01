#!/usr/bin/env sh
# Always-loaded context budget — the single source for the ceilings, and the
# inventory of what else gets billed.
#
# Called from lefthook's pre-commit and .github/workflows/lint.yml. Both call
# sites are one line; the numbers and the reasoning live here, once.
#
# Usage: scripts/context-budget.sh [file...]
#   With no arguments, checks every capped file. With arguments (lefthook passes
#   staged files), checks only the capped ones among them. The link inventory
#   runs either way — it is a property of boomfile.toml, not of what is staged.
#
# WHY A CEILING: these files are symlinked into ~/.claude/ and loaded before
# every task, so every byte is billed to every request of every session. A
# ceiling is what makes a cut permanent: past this, something goes out before
# anything comes in.
#
# WHY PER-FILE: a ceiling set too close to current size stops forcing
# DISPLACEMENT and starts forcing THRASH — you delete whatever is cheapest, not
# whatever is least worth loading. Each leaves roughly a fifth free.
#
# THE VENDOR NUMBER, AND HOW MUCH STRICTER THIS IS. Anthropic's published
# guidance is "keep CLAUDE.md under 200 lines", and warns that a bloated one
# makes Claude ignore the instructions inside it. 3000 and 2500 bytes are both
# around 40 lines: roughly 5x stricter, and nothing in the client enforces
# either. Keeping the stricter number is a choice and it stays; writing it down
# WITHOUT the number it is stricter than is what makes an invented ceiling
# indistinguishable from a measured one. It also has a recorded cost — see
# DECISIONS.md, "the byte ceiling was destroying guidance a free mechanism
# holds", which is why dot-claude/rules/ exists.
#
# WHY AN EXPLICIT LIST, NEVER A *.md GLOB: DECISIONS.md is deliberately UNCAPPED.
# It is not symlinked into ~/.claude/, so capping the overflow destination would
# push content back into the loaded file, inverting the whole mechanism.
#
# WHY THE DATE BAN: a date makes a sentence a record rather than a rule, so it is
# the cheap proxy for the whole rotting class. No false-positive risk: a full
# YYYY-MM-DD has no business in an instruction file.
#
# WHY THE LINK INVENTORY: every `dst = "~/.claude/…"` in boomfile.toml must be
# classified below or this fails, so a new link is a decision instead of a drift.
#
# WHAT WENT, 2026-09-01: a 22-line awk HTML-comment stripper (the client strips
# them, so they are free — but neither capped file has ever contained one, so it
# stripped nothing), its fenced-block bail-out, and a git-grep pass forbidding
# prose from restating two counts this repo computes. `wc -c` is the measurement
# now. See DECISIONS.md.
set -eu

BOOMFILE=${BOOMFILE:-boomfile.toml}

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

# ── per-file ceilings ─────────────────────────────────────────────────
if [ "$#" -eq 0 ]; then
  set -- dot-claude/CLAUDE.md CLAUDE.md
fi

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
  echo "  already enforced      -> nowhere. Describing a control is not the control."
  exit 1
fi
