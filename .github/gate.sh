#!/bin/bash
# The repo settings that are not files, as one idempotent command run by the owner:
#   .github/gate.sh [owner/repo] [check]      (defaults: origin's repo, and `lint`)
#   .github/gate.sh --check <owner/repo | owner>...   read-only; exits 1 on drift, naming the fix
# GitHub is the gate: the default branch takes pull requests only, squash-merged once GitHub
# Actions (app 15368) reports the one required check passing, with no bypass for anyone, the owner
# included; a status anyone else posts under that name blocks the merge. The branch need not be up
# to date: parallel agent PRs would otherwise wait behind each other, and a push to main re-runs
# the check. The squash commit carries the PR's body, a branch that fell behind can be updated from
# the PR, and Issues stay on for upkeep's failure reports. Actions tokens read by default, never
# approve a pull request, and run only SHA-pinned actions. Secret scanning and push protection stop
# a token before it lands, a reporter can file a vulnerability privately, and Dependabot's security
# updates skip its version cooldown. Rulesets on a private repo need a paid plan; everything here is
# free on a public one.
set -euo pipefail

settings='{
  "has_issues": true,
  "allow_auto_merge": true,
  "delete_branch_on_merge": true,
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "allow_update_branch": true,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY"
}'
security='{"security_and_analysis": {
  "secret_scanning": { "status": "enabled" },
  "secret_scanning_push_protection": { "status": "enabled" }
}}'
actions='{ "enabled": true, "allowed_actions": "all", "sha_pinning_required": true }'
tokens='{ "default_workflow_permissions": "read", "can_approve_pull_request_reviews": false }'
ruleset() {
  cat << EOF
{
  "name": "default-branch-protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": false,
        "required_status_checks": [{ "context": "$1", "integration_id": 15368 }] } },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash"] } }
  ]
}
EOF
}

# Every ruleset that guards the default branch, whatever it is named: gate.sh keeps one.
guards() {
  local all
  all=$(gh api "repos/$1/rulesets" --jq '.[] | select(.target == "branch") | .id' 2>&1) || {
    # A private repo on a free plan has no rulesets to read: it was never gated.
    grep -qE 'HTTP 40[34]' <<< "$all" && return 0
    echo "$all" >&2 && return 1
  }
  for id in $all; do
    gh api "repos/$1/rulesets/$id" --jq \
      'select(.conditions.ref_name.include | any(. == "~DEFAULT_BRANCH" or . == "~ALL")) | .id'
  done
}

# Whether $1 holds $2: every array and scalar $2 declares, with rules compared by type.
holds() {
  jq -e --argjson want "$2" '
    def norm: if type == "object" and has("rules") then .rules |= sort_by(.type) else . end;
    (norm) as $have | ($want | norm) as $w
    | all($w | paths(type != "object"); . as $p | ($have | getpath($p)) == ($w | getpath($p)))
    and (if $w | has("rules") then ($have.rules | map(.type)) == ($w.rules | map(.type)) else true end)
  ' <<< "$1" > /dev/null
}

check() {
  local repo=$1 ids id live name drift=()
  ids=$(guards "$repo")
  [ -n "$ids" ] || return 0
  [ "$(wc -l <<< "$ids")" -eq 1 ] || drift+=("$(wc -l <<< "$ids" | tr -d ' ') rulesets guard the default branch")
  # The ruleset that requires a check names it; with none, the owner picks the aggregate job.
  for id in $ids; do
    live=$(gh api "repos/$repo/rulesets/$id")
    name=$(jq -r '[.rules[] | select(.type == "required_status_checks")
      | .parameters.required_status_checks[0].context][0] // empty' <<< "$live")
    [ -z "$name" ] || break
  done
  name=${name:-<required check>}
  holds "$live" "$(ruleset "$name")" || drift+=("ruleset")
  holds "$(gh api "repos/$repo")" "$settings" || drift+=("merge settings")
  if [ "$(gh api "repos/$repo" --jq .visibility)" = public ]; then
    holds "$(gh api "repos/$repo")" "$security" || drift+=("push protection")
    holds "$(gh api "repos/$repo/private-vulnerability-reporting")" '{"enabled": true}' ||
      drift+=("private reporting")
  fi
  holds "$(gh api "repos/$repo/actions/permissions")" "$actions" || drift+=("action pinning")
  holds "$(gh api "repos/$repo/actions/permissions/workflow")" "$tokens" || drift+=("token permissions")
  gh api --silent "repos/$repo/vulnerability-alerts" 2> /dev/null || drift+=("Dependabot alerts")
  holds "$(gh api "repos/$repo/automated-security-fixes")" '{"enabled": true, "paused": false}' ||
    drift+=("security updates")
  [ ${#drift[@]} -eq 0 ] && return 0
  local IFS=,
  echo "gate: $repo drifted (${drift[*]}); fix: ! .github/gate.sh $repo \"$name\""
  return 1
}

if [ "${1:-}" = --check ]; then
  shift
  failed=0
  for target in "$@"; do
    if [[ $target == */* ]]; then
      repos=$target
    else
      repos=$(gh repo list "$target" --no-archived --source --limit 500 --json nameWithOwner --jq '.[].nameWithOwner')
    fi
    for repo in $repos; do check "$repo" || failed=1; done
  done
  exit "$failed"
fi

repo=${1:-$(gh repo view "$(git remote get-url origin)" --json nameWithOwner --jq .nameWithOwner)}
name=${2:-lint}

gh api -X PATCH "repos/$repo" --input - <<< "$settings" > /dev/null
# Free on a public repo only; a private one without Secret Protection answers 422.
if [ "$(gh api "repos/$repo" --jq .visibility)" = public ]; then
  gh api -X PATCH "repos/$repo" --input - <<< "$security" > /dev/null
  gh api -X PUT "repos/$repo/private-vulnerability-reporting" > /dev/null
fi
gh api -X PUT "repos/$repo/vulnerability-alerts" > /dev/null
gh api -X PUT "repos/$repo/automated-security-fixes" > /dev/null
gh api -X PUT "repos/$repo/actions/permissions" --input - <<< "$actions" > /dev/null
gh api -X PUT "repos/$repo/actions/permissions/workflow" --input - <<< "$tokens" > /dev/null

ids=$(guards "$repo")
first=${ids%%$'\n'*}
if [ -n "$first" ]; then
  ruleset "$name" | gh api -X PUT "repos/$repo/rulesets/$first" --input - > /dev/null
else
  ruleset "$name" | gh api -X POST "repos/$repo/rulesets" --input - > /dev/null
fi
# Rulesets aggregate, so another one guarding the branch keeps its rules; its owner deletes it.
for id in $(tail -n +2 <<< "$ids"); do
  echo "gate: ruleset $id also guards the default branch; run: gh api -X DELETE repos/$repo/rulesets/$id"
done
echo "gate: $repo converged"
