#!/bin/bash
# The source applied into a temporary home and verified; then what verify cannot see.
# Writes only under a temp directory, so it runs anywhere: CI, a Mac, a web session.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
home=$tmp/home
mkdir "$home"
cz=(chezmoi --source "$root" --config "$tmp/chezmoi.toml" --persistent-state "$tmp/chezmoi.db" --destination "$home")

"${cz[@]}" init
"${cz[@]}" apply --exclude scripts
"${cz[@]}" verify --exclude scripts
# `--exclude scripts` skips rendering them; this renders every script and runs none.
"${cz[@]}" apply --dry-run

# settings.json: the two shapes run_after_40-provision.sh loops over, every git pair counted in.
settings=$home/.claude/settings.json
jq -e 'all(.extraKnownMarketplaces[]; .source.repo) and any(.enabledPlugins[]; .)' "$settings" > /dev/null
test "$(jq -r '.env.GIT_CONFIG_COUNT' "$settings")" = \
  "$(jq '[.env | keys[] | select(startswith("GIT_CONFIG_KEY_"))] | length' "$settings")"
# What the app writes survives an apply, and a declared value is restored.
jq '. + {appWrote: true} | .enabledPlugins += {"toggled@elsewhere": false} | .autoMemoryEnabled = true' \
  "$settings" > "$tmp/edited" && cat "$tmp/edited" > "$settings"
"${cz[@]}" apply --force --exclude scripts
jq -e '.appWrote and .enabledPlugins["toggled@elsewhere"] == false and .autoMemoryEnabled == false' \
  "$settings" > /dev/null
# A file already holding every declared value is not drift, in whatever key order the app wrote.
jq '{appFirst: true} + .' "$settings" > "$tmp/edited" && cat "$tmp/edited" > "$settings"
"${cz[@]}" verify --exclude scripts

(
  export HOME="$home" XDG_CONFIG_HOME="$home/.config"
  unset GIT_CONFIG_COUNT
  # The applied login shell starts; an rc file that exits fails here (lint's `zsh -n` has syntax).
  zsh -l -i -c 'echo shell ok' > /dev/null
  # git parses the rendered file, gh is the last github.com helper in it, and commits sign.
  test "$(git config --global --get-all credential.https://github.com.helper | tail -1)" = '!gh auth git-credential'
  test "$(git config --global --get commit.gpgSign)" = true
  grep -q 'Group Containers' "$home/.ssh/config"
  # A work org's GitHub remote commits as work, in any URL form and either case; anything else as
  # alxjrvs.
  repo=$tmp/repo
  git init -q "$repo"
  email() {
    git -C "$repo" remote remove origin 2> /dev/null || true
    git -C "$repo" remote add origin "$1"
    git -C "$repo" config user.email
  }
  test "$(email https://github.com/TheGnarCo/app.git)" = alex@thegnar.co
  test "$(email git@github.com:criterium/app.git)" = alex@thegnar.co
  test "$(email ssh://git@github.com/massgov/app.git)" = alex@thegnar.co
  test "$(email https://gitlab.com/massgov/app.git)" = alxjrvs@gmail.com
  test "$(email https://github.com/alxjrvs/dotFiles.git)" = alxjrvs@gmail.com
  # The git pairs settings.json hands every agent session, read back through git. Last: the
  # first value is `false` and would mask the signing assertion above.
  eval "$(jq -r '.env | to_entries[] | select(.key | startswith("GIT_CONFIG_")) |
    "export \(.key)=\(.value | @sh)"' "$settings")"
  test "$(git config --get commit.gpgSign)" = false
)
echo "apply-check: ok"
