#!/bin/bash
# The repo settings that are not files, as one idempotent command run by the owner:
#   .github/gate.sh [owner/repo]     (defaults to the checkout's repo)
# GitHub is the gate: the default branch takes pull requests only, squash-merged once the check
# named `lint` passes on an up-to-date branch, with no bypass for anyone, the owner included.
# Secret scanning and push protection stop a token before it lands. Rulesets on a private repo
# need a paid plan; everything here is free on a public one.
set -euo pipefail
repo=${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}

gh api -X PATCH "repos/$repo" --input - > /dev/null << 'EOF'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true,
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "COMMIT_MESSAGES",
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
EOF

ruleset=$(
  cat << 'EOF'
{
  "name": "default-branch-protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false,
        "required_status_checks": [{ "context": "lint" }] } },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "require_extra_approval_for_unattributed_changes": true,
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
