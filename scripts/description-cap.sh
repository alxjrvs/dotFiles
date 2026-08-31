#!/usr/bin/env sh
# Frontmatter description cap for SKILLS AND SUBAGENTS — the single source, run
# by both lefthook and CI.
#
# WHY IT EXISTS. A skill's or subagent's `description:` is loaded into every
# session so the model can decide whether it is relevant; the body is not. A
# description that grows into a summary is a permanent tax on every request, paid
# to explain something that may never be invoked.
#
# WHY AGENTS TOO. boomfile.toml links dot-claude/agents/ into ~/.claude/ as well,
# and a subagent's description is billed on the same terms. context-budget.sh's
# link inventory asserts that this script covers both.
set -eu

CAP=60

# A skill BODY is not always-loaded, but it loads in full the moment the skill
# fires, so an oversized one taxes every invocation to carry branches most of
# them never touch. A ceiling on the BODY only, and only for skills — an agent
# file has no body worth capping. Progressive disclosure is the escape: move the
# inventory to references/ and link it. Set well above the correctly-sized skills
# so it forces a split rather than nagging.
BODY_CAP=${BODY_CAP:-12000}

fail=0

if [ "$#" -eq 0 ]; then
  set -- dot-claude/skills/*/SKILL.md dot-claude/agents/*.md
fi

# A glob that matches nothing, or an explicit path that does not exist, is a
# gate that checked nothing — it must fail, not be skipped.
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

  # YAML lets a scalar span lines. A one-line parser scores a folded block
  # (`description: >-`) as the single word `>-`, which lets any skill carry an
  # unbounded description past a gate reporting `ok (1 words)`. Read the whole
  # scalar.
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

  case "$f" in
    *SKILL.md)
      b=$(wc -c < "$f" | tr -d ' ')
      if [ "$b" -gt "$BODY_CAP" ]; then
        echo "$f: body is $b bytes (cap $BODY_CAP) — it loads in full whenever the skill fires"
        echo "   move the inventory to references/ and link it from the procedure"
        fail=1
      fi
      ;;
  esac
done

[ "$fail" -eq 0 ] || exit 1
