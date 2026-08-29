#!/usr/bin/env sh
# Regenerate DECISIONS.md's table of contents in place.
#
# WHY. The file is the destination for every reason, incident and measurement in
# this setup, and it is deliberately uncapped because it is not symlinked into
# ~/.claude/ and so costs nothing per session. That is the right trade, but it
# means the file only grows: 80-odd headings with no index, where answering "why
# does X exist?" was a full-file read.
#
# The cost landed on the thing it was supposed to make cheap. CLAUDE.md's routing
# table sends a reason here, and boomfile.toml's long comment blocks are supposed
# to shrink to a pointer — but a pointer is only cheap to write if the target is
# findable, so the prose stayed inline instead.
#
# GENERATED, NOT MAINTAINED. A hand-written index is a second copy of the
# headings that drifts from the first, which is the failure this repo keeps
# finding everywhere else. `--check` fails when it is stale; no argument
# rewrites it.
set -eu

FILE=${FILE:-dot-claude/DECISIONS.md}
START='<!-- toc:start -->'
END='<!-- toc:end -->'

[ -f "$FILE" ] || {
  echo "decisions-toc: no $FILE" >&2
  exit 2
}

grep -qF "$START" "$FILE" || {
  echo "decisions-toc: $FILE has no $START marker" >&2
  exit 2
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# `## ` always; `### ` only inside a section big enough to need it.
#
# This used to index `## ` alone, reasoning that "the `### ` level is detail
# within an entry; indexing it would make the index long enough to need its own
# index". Sound in general, and measurably wrong for this file in particular: 80
# of 114 headings (70%) were unindexed, and the two largest sections — about 28%
# of the file between them — were one TOC line each. The index was longest
# exactly where it was least useful, which is the opposite of what an index is
# for.
#
# So the rule is by SIZE, not by level. A section under the threshold stays a
# single line, because for those the original reasoning holds. A section over it
# gets its `### ` children nested underneath, because at that size "find the
# section, then read 500 lines" is the full-file read the index was supposed to
# replace. Sections cross the threshold on their own as they grow, so nothing has
# to be maintained.
BIG_SECTION_BYTES=${BIG_SECTION_BYTES:-8000}
awk -v s="$START" -v e="$END" '
  $0 == s { print; inblock=1; next }
  $0 == e { inblock=0 }
  !inblock { print }
' "$FILE" > "$tmp/stripped"

# Two passes. The first measures each `## ` section so the second knows which
# ones are big enough to expand — a section's size is not knowable until the next
# one starts, so it cannot be decided in a single streaming pass.
awk '
  /^## / { if (sec != "") print sec "\t" bytes; sec = substr($0, 4); bytes = 0; next }
  { bytes += length($0) + 1 }
  END { if (sec != "") print sec "\t" bytes }
' "$tmp/stripped" > "$tmp/sizes"

awk -v big="$BIG_SECTION_BYTES" -v sizes="$tmp/sizes" '
  function anchor(t,   a) {
    a = tolower(t)
    gsub(/[^a-z0-9 -]/, "", a)
    gsub(/ /, "-", a)
    return a
  }
  BEGIN {
    while ((getline line < sizes) > 0) {
      split(line, f, "\t")
      size[f[1]] = f[2] + 0
    }
    close(sizes)
  }
  /^## / {
    title = substr($0, 4)
    expand = (size[title] >= big)
    printf "- [%s](#%s)\n", title, anchor(title)
    next
  }
  /^### / {
    if (!expand) next
    title = substr($0, 5)
    printf "  - [%s](#%s)\n", title, anchor(title)
  }
' "$tmp/stripped" > "$tmp/toc"

awk -v s="$START" -v e="$END" -v tocfile="$tmp/toc" '
  $0 == s {
    print
    while ((getline line < tocfile) > 0) print line
    close(tocfile)
    print e
    skip = 1
    next
  }
  skip && $0 == e { skip = 0; next }
  skip { next }
  { print }
' "$tmp/stripped" > "$tmp/out"

if [ "${1:-}" = "--check" ]; then
  if cmp -s "$tmp/out" "$FILE"; then
    echo "ok decisions-toc ($(wc -l < "$tmp/toc" | tr -d ' ') entries)"
    exit 0
  fi
  echo "$FILE: table of contents is stale — run scripts/decisions-toc.sh"
  exit 1
fi

cat "$tmp/out" > "$FILE"
echo "ok decisions-toc ($(wc -l < "$tmp/toc" | tr -d ' ') entries, rewritten)"
