#!/usr/bin/env sh
# Personal identifiers outside the places a forker is told to look.
#
# README's "Forking this repo" section lists what has to change on a fork,
# ordered by what breaks first. A list like that rots the moment a new hardcoded
# name lands somewhere it does not mention — and the failure is silent and
# nasty: a forker's agent commits get authored as someone else, or `boom verify`
# fails against a 1Password vault that was never theirs.
#
# So the list is enforced rather than maintained. Every file that legitimately
# names the owner is enumerated below; anywhere else, the name is drift.
#
# WHY NOT JUST BAN IT EVERYWHERE. Several of these files must name the owner to
# work at all — the git identity IS the owner, the vault reference IS the vault.
# The point is not to remove the name, it is to keep it inside the set the
# README documents, so "what do I change on a fork" has one answer that cannot
# quietly stop being true.
set -eu

OWNER=${OWNER:-alxjrvs}

# Two groups, deliberately kept apart -- the distinction IS the point.
#
# GROUP 1: a forker must edit these, and README's "Forking this repo" says so in
# the order they break. Adding a file here without adding it there is how the
# list stops being true.
#
# GROUP 2: names the owner but is NOT configuration a forker changes -- an
# upstream URL (`alxjrvs/boom` is the tool, and a forker keeps using it), prose
# describing a past incident, or a test fixture that needs a concrete owner to
# assert against. These would be actively wrong to "genericize": a fixture with
# a fake owner tests nothing, and an incident that happened to a named file did
# happen to that file.
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
launchd/com.alxjrvs.boom-verify.plist
launchd/com.alxjrvs.capslock-control.plist
hooks/claude_statusline.ts
CLAUDE.md
Brewfile
dot-claude/DECISIONS.md
dot-claude/SETTINGS.md
dot-claude/REFERENCE.md
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
