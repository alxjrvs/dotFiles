#!/bin/bash
# Upkeep converges only a main whose `lint` passed on GitHub Actions. A merge made with
# GITHUB_TOKEN (Dependabot's, or an agent's auto-merge) starts no run on main, so its pull
# request's head answers for it, but only when the head's tree is main's tree. Otherwise main earns
# its own run, dispatched here, and tonight's converge waits for it. Anything else stops the
# converge too: a failure, a run still going, an API error. Run from inside the repo; gh fills
# {owner}/{repo} from it.
set -euo pipefail
lint() {
  gh api "repos/{owner}/{repo}/commits/$1/check-runs?check_name=lint&app_id=15368" \
    --jq 'if .total_count == 0 then "none" else .check_runs[0].conclusion // "pending" end'
}
tree() { gh api "repos/{owner}/{repo}/commits/$1" --jq .commit.tree.sha; }
state=$(lint main)
if [ "$state" = none ]; then
  head=$(gh api "repos/{owner}/{repo}/commits/main/pulls" --jq '.[0].head.sha // empty')
  if [ -n "$head" ] && [ "$(tree "$head")" = "$(tree main)" ]; then
    state=$(lint "$head")
  else
    gh workflow run lint.yml --ref main
    state="not yet run (dispatched)"
  fi
fi
[ "$state" = success ] || { echo "main-green: main's lint is $state; not converging" >&2 && exit 1; }
