#!/bin/bash
# The source applied into a temporary home and verified; then what verify cannot see.
# Writes only under a temp directory, so it is safe anywhere: a Mac, CI and a web session.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
# No trailing slash from TMPDIR: chezmoi prints targets with single slashes, and $home must match.
tmp=${TMPDIR:-/tmp}
tmp=$(mktemp -d "${tmp%/}/apply-check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
home=$tmp/home
mkdir "$home"
cz=(chezmoi --source "$root" --config "$tmp/chezmoi.toml" --persistent-state "$tmp/chezmoi.db" --destination "$home")

"${cz[@]}" init --promptBool "personal Mac=true"
data=$("${cz[@]}" data --format json)
personal=$(jq -r .email <<< "$data")
work=$(jq -r .workEmail <<< "$data")
# What the exact_ directories, .chezmoiignore and the remove lists must leave alone, seeded first and
# checked after: one dropped ignore line once deleted ~/.local/bin/claude with every check green.
mkdir -p "$home/.local/bin" && touch "$home/.local/bin/chezmoi"
survivors=(.local/bin/mise .local/bin/claude Code/repo/work .ssh/known_hosts
  Library/LaunchAgents/sh.brew.x.plist Library/LaunchAgents/com.valvesoftware.x.plist
  Library/LaunchAgents/com.google.GoogleUpdater.x.plist)
for f in "${survivors[@]}"; do
  mkdir -p "$home/${f%/*}"
  echo '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>' > "$home/$f"
done
"${cz[@]}" apply --exclude scripts
for f in "${survivors[@]}"; do
  [ -e "$home/$f" ] || { echo "apply-check: apply deleted ~/$f" >&2 && exit 1; }
done
# chezmoi's installer copy is the one exception: mise owns chezmoi after the first apply.
[ ! -e "$home/.local/bin/chezmoi" ] || { echo "apply-check: the installer's chezmoi survived" >&2 && exit 1; }
# An employer's agent and CLI: a personal Mac's exact_ directories remove them, a work Mac's keep
# them.
employer=(Library/LaunchAgents/com.employer.agent.plist .local/bin/employer-cli)
seed() { for f in "${employer[@]}"; do echo '<plist version="1.0"><dict/></plist>' > "$1/$f"; done; }
seed "$home"
"${cz[@]}" apply --exclude scripts
for f in "${employer[@]}"; do
  [ ! -e "$home/$f" ] || { echo "apply-check: a personal Mac kept ~/$f" >&2 && exit 1; }
done
office=$tmp/office
mkdir -p "$office/Library/LaunchAgents" "$office/.local/bin"
oz=(chezmoi --source "$root" --config "$tmp/office.toml" --persistent-state "$tmp/office.db" --destination "$office")
"${oz[@]}" init --promptBool "personal Mac=false"
seed "$office"
touch "$office/.local/bin/chezmoi"
legacy=Library/LaunchAgents/com.$(jq -r .github <<< "$data").upkeep.plist
echo '<plist version="1.0"><dict/></plist>' > "$office/$legacy"
"${oz[@]}" apply --exclude scripts
[ ! -e "$office/$legacy" ] || { echo "apply-check: a work Mac kept the old ~/$legacy" >&2 && exit 1; }
for f in "${employer[@]}"; do
  [ -e "$office/$f" ] || { echo "apply-check: a work Mac lost ~/$f" >&2 && exit 1; }
done
[ ! -e "$office/.local/bin/chezmoi" ] || { echo "apply-check: a work Mac kept the installer's chezmoi" >&2 && exit 1; }
[ -e "$office/Library/LaunchAgents/local.dotfiles.upkeep.plist" ] ||
  { echo "apply-check: a work Mac lost this repo's own agents" >&2 && exit 1; }
"${cz[@]}" verify --exclude scripts
# `--exclude scripts` skips rendering them; this renders every script and runs none.
"${cz[@]}" apply --dry-run

# A deleted source leaves its target behind, so every file main manages is still managed here,
# if only as a `remove_` entry that deletes it. Dropping a `remove_` entry later is fine: once
# applied it has done its work.
base=$tmp/base
mkdir "$base"
git -C "$root" archive "$(git -C "$root" merge-base HEAD origin/main)" | tar -x -C "$base"
was=$(chezmoi --source "$base" --destination "$home" managed --exclude scripts,externals,remove,dirs | sort)
now=$("${cz[@]}" managed --exclude scripts,externals,dirs | sort)
removed=$("${cz[@]}" managed --include remove)
# An exact_ directory deletes whatever it stops declaring, so its old entries need no remove_.
while read -r dir; do
  removed+=$'\n'$("${cz[@]}" target-path "$dir" | sed "s|^$home/||")
done < <(find "$root/home" -type d -name 'exact_*')
# A Mac's config was rendered by main's template: HEAD must apply over it (#449 did not).
upgrade=(chezmoi --source "$root" --config "$tmp/upgrade.toml" --persistent-state "$tmp/upgrade.db"
  --destination "$tmp/upgrade")
mkdir "$tmp/upgrade"
chezmoi --source "$base" --config "$tmp/upgrade.toml" --persistent-state "$tmp/upgrade.db" \
  --destination "$tmp/upgrade" init --promptBool "personal Mac=true" > /dev/null
"${upgrade[@]}" apply --dry-run > /dev/null
comm -23 <(printf '%s\n' "$was") <(printf '%s\n' "$now") |
  while read -r target; do
    path=$target
    until printf '%s\n' "$removed" | grep -qxF "$path"; do
      [ "$path" != "${path%/*}" ] || { echo "apply-check: ~/$target lost its source; add a remove_ entry" >&2 && exit 1; }
      path=${path%/*}
    done
  done

# settings.json: every git pair the agent env declares is counted in.
settings=$home/.claude/settings.json
test "$(jq -r '.env.GIT_CONFIG_COUNT' "$settings")" = \
  "$(jq '[.env | keys[] | select(startswith("GIT_CONFIG_KEY_"))] | length' "$settings")"
# What the app writes survives an apply, and a declared value is restored.
jq '. + {appWrote: true} | .enabledPlugins += {"toggled@elsewhere": false} | .autoMemoryEnabled = true' \
  "$settings" > "$tmp/edited" && cat "$tmp/edited" > "$settings"
"${cz[@]}" apply --force --exclude scripts
jq -e '.appWrote and .enabledPlugins["toggled@elsewhere"] == false and .autoMemoryEnabled == false' \
  "$settings" > /dev/null
# A declared null retires its entry: a marketplace the app still lists is removed, and never
# written back as null.
jq '.extraKnownMarketplaces += {"1password": {"source": {"source": "github", "repo": "x/y"}}}' \
  "$settings" > "$tmp/edited" && cat "$tmp/edited" > "$settings"
"${cz[@]}" apply --force --exclude scripts
jq -e '.extraKnownMarketplaces | has("1password") | not' "$settings" > /dev/null
jq -e '[.. | select(. == null)] | length == 0' "$settings" > /dev/null
# A file already holding every declared value is not drift, in whatever key order the app wrote.
jq '{appFirst: true} + .' "$settings" > "$tmp/edited" && cat "$tmp/edited" > "$settings"
"${cz[@]}" verify --exclude scripts
# Rendered TOML parses: lint parses only the plain .toml sources, not templates.
mise config get --file "$home/.config/1Password/ssh/agent.toml" > /dev/null

# On a Mac: the LaunchAgents parse and every Brewfile entry resolves, so a typo fails here and not
# halfway through an apply. Homebrew's cache goes under $tmp, so the check writes nowhere else.
if [ "$(uname -s)" = Darwin ]; then
  export HOMEBREW_CACHE=$tmp/brew HOMEBREW_NO_ANALYTICS=1
  plutil -lint -s "$home"/Library/LaunchAgents/*.plist
  brewfile=$home/.config/homebrew/Brewfile
  brew bundle list --formula --file="$brewfile" | xargs brew info --formula --json=v2 > /dev/null
  brew bundle list --cask --file="$brewfile" | xargs brew info --cask --json=v2 > /dev/null
fi

(
  export HOME="$home" XDG_CONFIG_HOME="$home/.config"
  unset GIT_CONFIG_COUNT
  # The applied login shell starts and says nothing on stderr: an rc file that exits or complains
  # fails here (lint's `zsh -n` has syntax).
  err=$(zsh -l -i -c true 2>&1 > /dev/null)
  [ -z "$err" ] || { printf 'apply-check: the shell said:\n%s\n' "$err" >&2 && exit 1; }
  # git parses the rendered file, its empty helper drops the system's osxkeychain, gh is the last
  # github.com helper in it, and commits sign.
  git config --global --get-all credential.helper | grep -qx ''
  test "$(git config --global --get-all credential.https://github.com.helper | tail -1)" = '!/opt/homebrew/bin/gh auth git-credential'
  test "$(git config --global --get commit.gpgSign)" = true
  grep -q 'Group Containers' "$home/.ssh/config"
  # Every work org's GitHub remote commits as workEmail, in any URL form and either case; anything
  # else as email.
  repo=$tmp/repo
  git init -q "$repo"
  email() {
    git -C "$repo" remote remove origin 2> /dev/null || true
    git -C "$repo" remote add origin "$1"
    git -C "$repo" config user.email
  }
  for org in $(jq -r '.workOrgs[]' <<< "$data"); do
    test "$(email "https://github.com/$org/app.git")" = "$work"
    test "$(email "git@github.com:$(tr '[:upper:]' '[:lower:]' <<< "$org")/app.git")" = "$work"
    test "$(email "ssh://git@github.com/$org/app.git")" = "$work"
    test "$(email "https://gitlab.com/$org/app.git")" = "$personal"
  done
  test "$(email "https://github.com/$(jq -r .github <<< "$data")/dotFiles.git")" = "$personal"
  # The git pairs settings.json hands every agent session, read back through git. Last: the
  # first value is `false` and would mask the signing assertion above.
  eval "$(jq -r '.env | to_entries[] | select(.key | startswith("GIT_CONFIG_")) |
    "export \(.key)=\(.value | @sh)"' "$settings")"
  test "$(git config --get commit.gpgSign)" = false
)
# A skills-directory plugin lands (a source name starting with `.` would be ignored).
test -f "$home/.claude/skills/ts-native/.claude-plugin/plugin.json" ||
  { echo "apply-check: the ts-native plugin did not land" >&2 && exit 1; }
echo "apply-check: ok"
