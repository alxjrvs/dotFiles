#!/usr/bin/env sh
# Frontmatter description cap for SKILLS AND SUBAGENTS — the single source, and
# enforced in both gates rather than only in CI.
#
# WHY IT EXISTS. A skill's or subagent's `description:` is loaded into every
# session so the model can decide whether it is relevant. The body is not. A
# description that grows into a summary is a permanent tax on every request, paid
# to explain something that may never be invoked — the same argument
# scripts/context-budget.sh makes for the two symlinked CLAUDE.md files.
#
# WHY AGENTS TOO, AND WHY THE RENAME. This was `skill-description-cap.sh` and
# read only dot-claude/skills/. But boomfile.toml links dot-claude/agents/ into
# ~/.claude/ as well, and a subagent's description is billed on exactly the same
# terms — so two of the seven always-loaded surfaces sat outside the only cap
# that governs them. context-budget.sh's link inventory now asserts that this
# script covers both, which is what makes that classification true rather than
# aspirational.
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
  set -- dot-claude/skills/*/SKILL.md dot-claude/agents/*.md
fi

# See settings-guardrails.sh. This one already defaults to a glob when called
# with no arguments, but the glob itself can match nothing — and an explicit
# path that does not exist was silently skipped rather than reported.
[ "$#" -gt 0 ] || {
  echo "no inputs — the skill/agent globs matched nothing, so no description was checked" >&2
  exit 1
}

for f in "$@"; do
  [ -f "$f" ] || {
    echo "$f: expected skill file is missing"
    fail=1
    continue
  }
  # Both shapes carry a billed description: a skill's SKILL.md and a subagent's
  # dot-claude/agents/<name>.md. Anything else a caller passes is ignored, so
  # lefthook can hand this its whole staged-file list.
  case "$f" in
    *SKILL.md) ;;
    dot-claude/agents/*.md) ;;
    */agents/*.md) ;;
    *) continue ;;
  esac

  # YAML lets a scalar span lines, and the previous one-line `awk` scored only
  # the FIRST line. For a folded block the first line is the indicator itself:
  #
  #     description: >-
  #       …four hundred words…
  #
  # scored as the single word `>-`, so ANY skill could carry an unbounded
  # description past a gate that reported `ok (1 words)`. The cap is the whole
  # point of this script, and that spelling removed it entirely.
  #
  # Only the frontmatter block is read, so a `description:` line in the body
  # cannot be mistaken for the real one.
  d=$(awk '
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm && /^---[[:space:]]*$/ { exit }
    !fm { next }
    !seen && /^description:[[:space:]]*/ {
      seen = 1
      val = $0
      sub(/^description:[[:space:]]*/, "", val)
      # `>`, `>-`, `|`, `|+` … or nothing: the text is on the indented lines
      # that follow, and continues until a line that is not indented.
      if (val ~ /^[|>][-+0-9]*[[:space:]]*$/ || val == "") { block = 1; val = "" }
      next
    }
    seen && block {
      if ($0 ~ /^[[:space:]]/) {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        val = val (val == "" ? "" : " ") line
        next
      }
      block = 0
    }
    END { print val }
  ' "$f")
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
