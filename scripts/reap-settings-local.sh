#!/usr/bin/env sh
# Remove `settings.local.json` files, archiving each before it goes.
#
# WHY. Machine-local override is not a pattern this setup uses: every divergence
# lives in the committed `settings.json` contract, and `.gitignore` says so.
# But Claude Code WRITES one on its own — an "always allow" click or a
# project-trust flow creates `settings.local.json` without asking — so the rule
# has been enforceable only against committing one, never against having one.
#
# That gap is not cosmetic. The file found on 2026-08-28 carried
# `Bash(gh api *)` in `permissions.allow`: POST and DELETE against any repo on
# GitHub, no prompt, under defaultMode auto. It sat there unreviewed because
# nothing in lefthook, CI or `boom verify` could see a file git was told to
# ignore. A permission that grants itself silently is the exact thing the
# committed contract exists to prevent.
#
# TWO MODES, because a `run` bound to `on = "sync"` is invisible to `verify` BY
# CONSTRUCTION — the lesson boomfile.toml already records where a hand-removed
# gh extension went unnoticed until the next sync silently reinstalled it.
#
#   (no args)  archive and remove. Wired to `on = "sync"`.
#   --check    exit 1 if any exists. Wired to `on = "verify"`, so a file that
#              appears BETWEEN syncs surfaces instead of waiting for the next one.
#
# ARCHIVED, NOT JUST DELETED. These files record permissions someone actually
# clicked "always allow" on. Throwing that away silently loses the evidence of
# what was approved and what keeps coming back; a copy costs nothing and makes
# the pattern visible.
#
# EXPLICIT PATHS, NEVER A SWEEP. This deletes files on every sync, so it may only
# ever touch paths named here. A `find ~/Code -name settings.local.json` would
# also delete one a colleague added deliberately in a shared repo, with no record
# and no consent. Add a path below to widen it; there is no glob on purpose.
set -eu

ARCHIVE=${BOOM_SETTINGS_LOCAL_ARCHIVE:-$HOME/.local/state/boom/settings-local-archive}

# The config repo, so this works from a `run` step (cwd = config repo) and from
# a shell anywhere else.
config_repo() {
  if command -v boom > /dev/null 2>&1; then
    boom where config 2> /dev/null && return 0
  fi
  pwd
}

paths() {
  # User scope: the one Claude Code writes on "always allow".
  echo "$HOME/.claude/settings.local.json"
  # Project scope for the config repo itself.
  repo=$(config_repo)
  [ -n "$repo" ] && echo "$repo/.claude/settings.local.json"
}

mode=${1:-reap}

found=0
removed=0

for f in $(paths); do
  [ -f "$f" ] || continue
  found=$((found + 1))

  if [ "$mode" = "--check" ]; then
    echo "$f exists — machine-local override is not a pattern this setup uses."
    echo "  It can grant permissions the committed contract never reviewed."
    echo "  Contents:"
    sed 's/^/    /' "$f"
    continue
  fi

  # A short, readable slug: the directory that OWNS the .claude dir. `home` for
  # user scope, the repo name for a project one. The full path is inside the
  # archived file's own directory structure if it is ever needed; a filename
  # built from a flattened absolute path is unreadable and sorts badly.
  owner=${f%/.claude/settings.local.json}
  if [ "$owner" = "$HOME" ]; then
    slug=home
  else
    slug=${owner##*/}
  fi
  slug=$(printf '%s' "$slug" | tr -c 'A-Za-z0-9._-' '-')
  stamp=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$ARCHIVE"
  cp "$f" "$ARCHIVE/$stamp-$slug.json"
  rm -f "$f"
  removed=$((removed + 1))
  echo "settings.local: removed $f"
  echo "  archived to $ARCHIVE/$stamp-$slug.json"
done

if [ "$mode" = "--check" ]; then
  [ "$found" -eq 0 ] || exit 1
  echo "ok settings.local (none present)"
  exit 0
fi

[ "$removed" -eq 0 ] || echo "settings.local: removed $removed (archived)"
exit 0
