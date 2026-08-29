#!/usr/bin/env sh
# Every rule in dot-claude/rules/ must carry `paths:` frontmatter.
#
# WHY. A path-scoped rule is free: it loads only when Claude reads a file
# matching one of its globs. A rule WITHOUT `paths:` is not — it "load[s] at
# launch with the same priority as .claude/CLAUDE.md", so it is billed to every
# request of every session, exactly like the file the rules directory exists to
# relieve.
#
# That makes the omission the whole failure mode. Nothing about a rule missing
# its frontmatter looks wrong: it still works, it still applies, it is simply now
# permanently loaded. Silent, and in the expensive direction — the same shape as
# the two defects context-budget.sh was carrying before it learned to measure
# post-strip bytes and to notice new links.
#
# So the rules directory is exempt from the byte ceiling ONLY on the condition
# this script asserts. Break the condition and the exemption is unearned.
#
# Usage: scripts/rules-scoped.sh [file...]
#   With no arguments, checks every rule. With arguments (lefthook passes staged
#   files), checks only the rules among them.
set -eu

DIR=${DIR:-dot-claude/rules}

if [ "$#" -eq 0 ]; then
  [ -d "$DIR" ] || {
    echo "rules-scoped: no $DIR — nothing was checked" >&2
    exit 1
  }
  # A `set --` on a glob that matches nothing leaves the literal pattern, which
  # would then fail the -f test below and report a confusing missing file. An
  # empty rules directory is legitimate, so say so and pass.
  set -- "$DIR"/*.md
  [ -f "$1" ] || {
    echo "ok rules-scoped (no rules in $DIR)"
    exit 0
  }
fi

fail=0
n=0

for f in "$@"; do
  case "$f" in
    */rules/*.md) ;;
    *) continue ;;
  esac
  [ -f "$f" ] || {
    echo "$f: expected rule file is missing"
    fail=1
    continue
  }
  n=$((n + 1))

  # Frontmatter only: a `paths:` mentioned in the body is prose, not config.
  #
  # The result is carried in a flag rather than an early `exit`. awk runs END
  # even when a rule calls exit, so an `END { exit 1 }` overrides the `exit 0`
  # that just fired and every rule reports as unscoped — which is what the first
  # version of this did, failing both correctly-scoped rules in the directory.
  if awk '
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm && /^---[[:space:]]*$/ { fm = 0; next }
    fm && /^paths:[[:space:]]*(\[.*)?$/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$f"; then
    echo "ok $f (path-scoped)"
  else
    echo "$f: no 'paths:' in frontmatter — this rule loads into EVERY session"
    fail=1
  fi
done

[ "$n" -gt 0 ] || {
  echo "rules-scoped: no rule files among the inputs — nothing was checked" >&2
  exit 1
}

[ "$fail" -eq 0 ] || {
  echo ""
  echo "A rule without 'paths:' is billed at launch like CLAUDE.md itself."
  echo "Either scope it:"
  echo "  ---"
  echo "  paths:"
  echo "    - \"**/some/glob/*.ts\""
  echo "  ---"
  echo "or put it in dot-claude/CLAUDE.md and pay for it deliberately, under the ceiling."
  exit 1
}
