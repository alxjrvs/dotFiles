#!/bin/bash
# The source applied into a temporary home, twice, and verified; then what verify cannot see.
# Writes only under a temp directory, so it runs anywhere: CI, a Mac, a web session.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
home=$tmp/home
mkdir "$home"
cz=(chezmoi --source "$root" --config "$tmp/chezmoi.toml" --persistent-state "$tmp/chezmoi.db" --destination "$home")

"${cz[@]}" init
# Twice, because both hosts are long-lived and this home is not: the second proves idempotence.
for _ in 1 2; do
  "${cz[@]}" apply --exclude scripts
  "${cz[@]}" verify --exclude scripts
done

# settings.json: the two shapes run_after_40-provision.sh loops over, every git pair counted in.
settings=$home/.claude/settings.json
jq -e '.extraKnownMarketplaces[].source.repo' "$settings" > /dev/null
jq -e '.enabledPlugins | to_entries | map(select(.value)) | length > 0' "$settings" > /dev/null
test "$(jq -r '.env.GIT_CONFIG_COUNT' "$settings")" = \
  "$(jq '[.env | keys[] | select(startswith("GIT_CONFIG_KEY_"))] | length' "$settings")"
# What the app writes survives an apply, its key order is not drift, and a declared value is
# restored.
jq -S '. + {appWrote: true} | .enabledPlugins += {"toggled@elsewhere": false} | .autoMemoryEnabled = true' \
  "$settings" > "$tmp/edited" && cat "$tmp/edited" > "$settings"
"${cz[@]}" apply --force --exclude scripts
jq -e '.appWrote and .enabledPlugins["toggled@elsewhere"] == false and .autoMemoryEnabled == false' \
  "$settings" > /dev/null
"${cz[@]}" verify --exclude scripts

# Every script renders: `--exclude scripts` filters by target name before the template runs, so
# a moved source file would leave the applies above green and fail a machine's first apply.
"${cz[@]}" managed --include scripts | while read -r script; do
  "${cz[@]}" cat "$home/$script" > /dev/null
done
# The Mac-only scripts are ignored by target name; only Linux exercises that.
if [ "$(uname)" = Linux ]; then
  test "$("${cz[@]}" managed --include scripts | sort | tr '\n' ' ')" = \
    '.chezmoiscripts/20-mise.sh .chezmoiscripts/40-provision.sh '
fi

(
  export HOME="$home" XDG_CONFIG_HOME="$home/.config"
  unset GIT_CONFIG_COUNT
  # The applied shell starts with none of the guarded tools present.
  zsh -l -i -c 'echo shell ok' > /dev/null
  # git parses the rendered file, gh is the last github.com helper in it, and the template took
  # this OS's branch: darwin signs, a container does not. A branch each, never `a && b || c`:
  # that runs c when b fails. And never a bare `! cmd`: it cannot fail under `set -e`.
  test "$(git config --global --get-all credential.https://github.com.helper | tail -1)" = '!gh auth git-credential'
  if [ "$(uname)" = Darwin ]; then
    test "$(git config --global --get commit.gpgSign)" = true
    grep -q 'Group Containers' "$home/.ssh/config"
  else
    test -z "$(git config --global --get commit.gpgSign)"
    if grep -q IdentityAgent "$home/.ssh/config"; then exit 1; fi
  fi
  # A work org's remote commits as work, any other as alxjrvs, in either URL form and case.
  repo=$tmp/repo
  git init -q "$repo"
  email() {
    git -C "$repo" remote remove origin 2> /dev/null || true
    git -C "$repo" remote add origin "$1"
    git -C "$repo" config user.email
  }
  test "$(email https://github.com/TheGnarCo/app.git)" = alex@thegnar.co
  test "$(email git@github.com:criterium/app.git)" = alex@thegnar.co
  test "$(email https://github.com/alxjrvs/dotFiles.git)" = alxjrvs@gmail.com
  test "$(email https://github.com/zsh-users/zsh-autosuggestions.git)" = alxjrvs@gmail.com
  # The git pairs settings.json hands every agent session, read back through git. Last: the
  # first value is `false` and would mask the signing assertion above.
  eval "$(jq -r '.env | to_entries[] | select(.key | startswith("GIT_CONFIG_")) |
    "export \(.key)=\(.value | @sh)"' "$settings")"
  test "$(git config --get commit.gpgSign)" = false
)
echo "apply-check: ok"
