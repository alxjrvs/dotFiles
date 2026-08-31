#!/usr/bin/env sh
# Personal identifiers outside the places a forker is told to look.
#
# README's "Forking this repo" section lists what has to change on a fork. A list
# like that rots the moment a new hardcoded name lands somewhere it does not
# mention — and the failure is silent: a forker's agent commits get authored as
# someone else, or `boom verify` fails against a vault that was never theirs. So
# a NEW hardcoded name cannot land unnoticed: every file that legitimately names
# the owner is enumerated below, and anywhere else the name is drift.
#
# Not a ban. Several of these files must name the owner to work at all — the git
# identity IS the owner, the vault reference IS the vault. The point is to keep
# the name inside the set the README documents. This checks its own allowlist,
# which is a superset of README's list; keeping README correct is a human job.
set -eu

OWNER=${OWNER:-alxjrvs}

# Two kinds of entry, and the distinction IS the point. A forker must edit some
# of these, and README's "Forking this repo" says so in the order they break;
# adding such a file here without adding it there is how that list stops being
# true. The rest name the owner but are NOT configuration a forker changes -- an
# upstream URL (`alxjrvs/boom` is the tool), prose about a past incident, or a
# test fixture that needs a concrete owner. Genericizing those would be actively
# wrong: a fixture with a fake owner tests nothing.
allowed() {
  cat << 'FILES'
LICENSE
README.md
.gitconfig
.gitmessage
agent-vault.txt
npm/publish.env
ssh/config
ssh/1password-agent.toml
boomfile.toml
dot-claude/settings.json
dot-claude/CLAUDE.md
dot-claude/hooks/guard-lib.sh
dot-claude/skills/butter-stack/SKILL.md
dot-claude/skills/butter-stack/references/stack.md
dot-claude/skills/agent-friendly-repo/SKILL.md
.claude/settings.json
launchd/com.alxjrvs.capslock-control.plist
hooks/claude_statusline.ts
CLAUDE.md
Brewfile
dot-claude/DECISIONS.md
dot-claude/hooks/repo-scope-guard.sh
dot-claude/hooks/tests/cases.tsv
dot-claude/hooks/tests/reposcope.sh
scripts/identity-drift.sh
scripts/plist-validity.sh
FILES
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

allowed | sort -u > "$tmp/allowed"
git grep -l -i -- "$OWNER" | sort -u > "$tmp/found" || true

unexpected=$(comm -23 "$tmp/found" "$tmp/allowed")

if [ -n "$unexpected" ]; then
  echo "'$OWNER' appears in files the README's forking section does not send a forker to:"
  echo "$unexpected" | sed 's/^/  /'
  echo ""
  echo "Either add the file to README's 'Forking this repo' AND to the allowed list"
  echo "in this script, or use a value that is not personal. A hardcoded owner that"
  echo "nobody is told about is the one that breaks a fork silently."
  exit 1
fi

echo "ok identity-drift ($(wc -l < "$tmp/found" | tr -d ' ') files name '$OWNER', all documented)"
