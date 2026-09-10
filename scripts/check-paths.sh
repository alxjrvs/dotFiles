#!/usr/bin/env bash
# Every in-repo path a tracked file MENTIONS must exist. This repo cross-references itself
# heavily — the README names the run scripts, comments name the file that supersedes them,
# GOTCHAS names the script it describes — and a rename leaves those pointing at nothing with
# no other check to notice. One did: the Brewfile pointed at run_after_00-claude-cli.sh.tmpl
# for months after the three-script consolidation.
#
# Only `home/`, `scripts/` and `docs/` prefixes — this repo's own layout, so a match is
# unambiguously a self-reference. `.github/` is deliberately NOT checked: docs here describe
# configuring OTHER repos, where `.github/dependabot.yml` names a file that is correctly
# absent from this one. A token with a glob is skipped too: `home/run_*` and `home/dot_config/*` are
# patterns, not paths, and expanding them would be guessing at intent.
set -uo pipefail
cd -- "$(git rev-parse --show-toplevel)" || exit 1

fail=0
while IFS=: read -r file path; do
  [ -e "$path" ] && continue
  printf 'FAIL %s\n     mentions %s, which does not exist\n' "$file" "$path"
  fail=1
done < <(
  git grep -hoIE '(home|scripts|docs)/[A-Za-z0-9_*./-]+' -- . |
    grep -v '[*]' |
    grep -E '\.[A-Za-z]+$|/$' |
    sort -u |
    while IFS= read -r p; do
      # Name the file that mentions it, so the failure is actionable.
      printf '%s:%s\n' "$(git grep -lIF -- "$p" | head -1)" "$p"
    done
)

[ "$fail" -eq 0 ] && echo "check-paths: every mentioned path exists"
exit "$fail"
