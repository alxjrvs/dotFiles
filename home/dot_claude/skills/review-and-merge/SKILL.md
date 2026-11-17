---
name: review-and-merge
description: Review the open pull requests of the current repository, or the one named, and turn on squash auto-merge for each that passes review and has green required checks; report the rest with the reason. Use for "review and merge", "review this PR", "review all open PRs", "review the open PRs and merge what's ready", "merge what's green".
argument-hint: [pr-number-or-url]
allowed-tools: Bash(gh pr list *) Bash(gh pr view *) Bash(gh pr diff *) Bash(gh pr checks *)
---

# Review and merge

The pull request named in `$ARGUMENTS`, or with none, every open one in the current repository
(`gh pr list`). Drafts are reviewed and reported, never merged.

For each pull request:

1. Read the repository's CLAUDE.md or AGENTS.md, then the description, the whole diff
   (`gh pr diff`) and the existing review comments. Review for correctness first, then for what
   the repository's own rules ask. Say what you could not verify.
2. `gh pr checks <n> --required`. Green means every required check passed. Pending is not green,
   and "no required checks" means the base branch has no gate.
3. Passes review, required checks green, no unresolved review thread, no conflict: turn on
   auto-merge with `gh pr merge <n> --auto --squash`. GitHub merges it; you never merge directly.
4. Anything else: leave it open. A finding goes on the pull request as a review comment where
   the repository is the owner's own, and in the report either way.

End with one line per pull request: number, title, `auto-merge on` or `left open`, and the reason.

## Limits

- Never merge, or turn on auto-merge for, a pull request whose base branch has no required
  check: auto-merge with no gate is an immediate merge. Report it instead.
- Never push to a default branch, and never bypass or change a ruleset or branch protection: no
  `--admin`, no bypass link, no settings change. A blocked merge is a line in the report.
- In a client's repository, or any the owner neither owns nor administers: review and report,
  and leave merging to that repository's own rules and people. Post nothing there unless asked.
- Fixing a finding is a separate request. This skill does not push to someone else's branch.
