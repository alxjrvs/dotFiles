---
name: rebase-prs
description: Rebase every open PR (or a named subset) in the current repo onto the fresh default branch and re-push; delegates stacked PRs to `gh stack sync` rather than walking them by hand. Use when the user says "rebase all open PRs against main", "get all my PRs up to date", "refresh the stack", or after the default branch has moved and several branches are behind. Automates a multi-PR fan-out alxjrvs does by hand.
---

# rebase-prs

Fan out the "rebase this branch onto fresh `main`" operation across many open PRs at once. Replaces manually walking each PR — the recurring "rebase all of them against main" request.

## First: is the target a stack?

If the branches in question are a **stack** (`gh stack view` reports one, or the user says "the stack"), **stop and use `gh stack sync`** — do not walk the branches by hand:

```
gh stack sync
```

That is the whole job for a stack, natively: it fetches, fast-forwards trunk, cascade-rebases each branch onto its *updated parent*, pushes them atomically (`--force-with-lease --atomic`), and re-syncs PR state. Hand-rolling the same cascade with per-branch `git switch` + `git rebase` is strictly worse — it force-pushes branch by branch (so a failure midway leaves the stack half-rebased, with children pointing at commits that no longer exist), and it can't reconcile the stack object on GitHub.

On a rebase conflict `gh stack sync` restores every branch to its original state and tells you to run `gh stack rebase` — resolve there, then re-run sync. Don't fall back to the manual loop below to "get past" a conflict.

The procedure below is for **independent** PRs that merely share a target. Use it when the branches are not a stack, or for the non-stack remainder alongside one.

## Procedure

1. **Freshen the target:**
   ```
   git fetch --all --prune
   ```
   Resolve the default branch once: `def=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's@^origin/@@')`, fall back to `main`.

2. **Enumerate the PRs to touch.** Default = all open PRs authored on this repo:
   ```
   gh pr list --state open --json number,headRefName,title,isDraft,mergeStateStatus
   ```
   If the user named a subset (labels, specific numbers), filter to those. If any of them turn out to be stacked, peel those off and hand them to `gh stack sync` per the section above rather than folding them into this loop.

3. **For each branch, rebase onto the fresh target.** Do NOT `git checkout <default>` — in a worktree that fails ("already used by worktree"); the checkout-guard hook will block it anyway. Instead operate per branch:
   ```
   git fetch origin <branch> && git switch <branch>
   git rebase origin/$def
   ```
   - **Conflicts:** stop on the first conflicted branch, resolve with full context, `git rebase --continue`, then carry on. Never `--skip` or blindly `-X theirs/ours`.
   - Re-push with lease: `git push --force-with-lease`.

4. **Prefer GitHub's own update when it's a clean fast-forward.** For branches that are merely behind (no conflicts), `gh pr update-branch --rebase <number>` does it server-side without a local checkout — cheaper than a local rebase. Fall back to the local rebase (step 3) only when that can't (conflicts, or the button isn't offered).

5. **Report** a table: PR #, branch, result (rebased & pushed / clean via GitHub / conflicts — needs attention / already up to date).

## Guardrails

- Never touch `main`/`master` itself — only the PR branches.
- **Never hand-roll a stack rebase.** `gh stack sync` is the native cascade; a per-branch loop force-pushes incrementally and can strand children on commits that no longer exist. If sync can't do it, `gh stack rebase` is the escape hatch — not this skill.
- Isolation: if branches are checked out across multiple worktrees, rebase each in its own worktree rather than thrashing one checkout between branches.
- Draft PRs are included by default; skip them only if asked.
- Stop and surface any branch whose rebase you can't cleanly resolve — don't force through a bad merge.
