#!/bin/bash
# The repo settings that are not files, as one idempotent command run by the owner:
#   .github/gate.sh [owner/repo] [check]     (defaults: origin's repo, and `lint`)
# GitHub is the gate: the default branch takes pull requests only, squash-merged once GitHub
# Actions (app 15368) reports the one required check passing, with no bypass for anyone, the owner
# included; a status anyone else posts under that name blocks the merge. The branch need not be up
# to date: parallel agent PRs would otherwise wait behind each other, and a push to main re-runs
# the check. The squash commit carries the PR's body, a branch that fell behind can be updated from
# the PR, and Issues stay on for upkeep's failure reports. Secret scanning and push protection stop
# a token before it lands, and Dependabot's security updates skip its version cooldown. Rulesets
# on a private repo need a paid plan; everything here is free on a public one.
set -euo pipefail
repo=${1:-$(gh repo view "$(git remote get-url origin)" --json nameWithOwner --jq .nameWithOwner)}
check=${2:-lint}

gh api -X PATCH "repos/$repo" --input - > /dev/null << 'EOF'
{
  "has_issues": true,
  "allow_auto_merge": true,
  "delete_branch_on_merge": true,
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "allow_update_branch": true,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY"
}
EOF
# Free on a public repo only; a private one without Secret Protection answers 422.
[ "$(gh api "repos/$repo" --jq .visibility)" != public ] ||
  gh api -X PATCH "repos/$repo" --input - > /dev/null << 'EOF'
{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
EOF
gh api -X PUT "repos/$repo/vulnerability-alerts" > /dev/null
gh api -X PUT "repos/$repo/automated-security-fixes" > /dev/null

ruleset=$(
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
        "required_status_checks": [{ "context": "$check", "integration_id": 15368 }] } },
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
)
id=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "default-branch-protection") | .id')
if [ -n "$id" ]; then
  printf '%s' "$ruleset" | gh api -X PUT "repos/$repo/rulesets/$id" --input - > /dev/null
else
  printf '%s' "$ruleset" | gh api -X POST "repos/$repo/rulesets" --input - > /dev/null
fi
echo "gate: $repo converged"
