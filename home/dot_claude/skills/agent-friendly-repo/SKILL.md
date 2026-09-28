---
name: agent-friendly-repo
description: Configure a GitHub repo for automated PR → auto-merge: squash-only merges, a branch-protection ruleset, stacked PRs via the official github/gh-stack, and optional Dependabot auto-merge. Use for "make this repo agent-friendly", "set up auto-merge", "align merge settings + branch protection", "set up stacked PRs", "auto-merge dependabot", "carry .env into worktrees".
disable-model-invocation: true
---

# agent-friendly-repo

Make the agent completion path, commit → push → PR → `gh pr merge --auto --squash`, land on a
repo with CI green for everyone and no human review gate. The settings are one idempotent
command, dotFiles' `.github/gate.sh`; this skill finds what it needs and hands it over. Why each
setting holds is in [`references/checklist.md`](references/checklist.md): read the slice the
request needs.

Reads and the report are unprompted. The writes are the owner's: an agent never changes a
repository's settings or rulesets, so the skill ends with `!` commands, which run as the owner.

1. **Resolve** the repo and its default branch:
   `gh repo view --json nameWithOwner,defaultBranchRef --jq '.nameWithOwner, .defaultBranchRef.name'`.
2. **Read** `gh api repos/$repo`, `gh api repos/$repo/branches/$def/protection` (absent is fine),
   `gh api repos/$repo/rulesets` and each ruleset, and the real check names:
   `gh api repos/$repo/commits/$def/check-runs --jq '.check_runs[].name' | sort -u`.
3. **Pick the one required check**: a single aggregate job that `needs:` every other job with
   `if: always()`. If there is none, open a PR that adds one (shape in the checklist) before the
   gate. Never require path-filtered jobs one by one: they strand PRs at "pending".
4. **Report** the difference from what gate.sh sets, then hand over
   `! ~/.local/share/chezmoi/.github/gate.sh $repo <check>` (it requires the check from GitHub
   Actions, so a posted status cannot pass it), and
   `! gh api -X DELETE repos/$repo/branches/$def/protection` only when classic protection exists:
   GitHub enforces the union of both, so the ruleset must be the only one.
5. **Only when asked**: Dependabot auto-merge (copy dotFiles'
   `.github/workflows/dependabot-auto-merge.yml`, after the checklist's preconditions), a
   `.worktreeinclude` for the gitignored files a build needs, `gh extension install github/gh-stack`.
6. **Verify** after the owner's run by repeating step 2, and report the merge settings, the ruleset
   and its required check, whether classic protection is gone, and stack readiness.

Never require a human review or add a bypass actor: either one stops the unattended path. Never
offer a merge queue as the cure for waiting on CI: GitHub has queues only on organization-owned
repos, and `GITHUB_TOKEN` cannot enqueue Dependabot's PRs. Never claim auto-merge lands a stack:
watch every layer green (`gh pr checks <pr> --watch`), then `gh stack merge --squash --yes`.
Only `github/gh-stack`, never a same-named community fork.
