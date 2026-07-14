---
name: ship
description: Ship the current worktree — verify, commit, rebase, push, open a PR, and enable auto-merge — in one step. Use when work is done and the user says "ship it", "commit + push + PR", "open a PR and auto-merge", or otherwise asks to land the branch. Encodes alxjrvs's standard completion pipeline so it never has to be re-typed.
---

# ship

The completion pipeline for a finished piece of work: **verify → commit → rebase → push → PR → auto-merge**. This is alxjrvs's documented standard (see `~/.claude/CLAUDE.md`, "Agent worktree & merge workflow"); running it as one skill replaces re-typing the steps every time.

Never run this on `main`/`master` directly — the rebase-guard hook denies a direct push to the default branch, and that is correct. You must be on a feature branch in a worktree.

## Steps

1. **Verify the change actually works.** Invoke the `verify` skill (or the repo's own check command — `bun run check:all`, `bun test`, `mise run ci`, etc.). Drive the affected flow, don't just typecheck. If verification fails, STOP and report — do not ship broken work.

2. **Stage and commit.** `git add -A` (or the specific paths), then a Conventional-Commit message (`feat:`/`fix:`/`chore:`/`docs:`…). The commit trailers (`Co-Authored-By`, `Claude-Session`) are appended by config — don't hand-add them. If there are already commits on the branch and only small fixups remain, amend or add a focused commit rather than one giant blob.

3. **Rebase onto the fresh target** *before pushing* — this keeps the rebase-guard a silent no-op:
   ```
   git fetch origin && git rebase origin/HEAD
   ```
   Resolve conflicts with full context if any. (`origin/HEAD` resolves to the default branch; use `origin/main` if it isn't set.)

4. **Push** the branch, force-with-lease if it was pushed before:
   ```
   git push -u origin HEAD          # first push
   git push --force-with-lease      # after a rebase of an already-pushed branch
   ```

5. **Open a draft PR** (unless the user asked for a ready one). Title mirrors the commit; body summarizes what changed and how it was verified, ending with the standard generated-with trailer:
   ```
   gh pr create --draft --fill
   ```

6. **Enable auto-merge** so GitHub's gated queue lands it once required checks pass (this is why the `Bash(gh pr merge:*)` permission rule exists):
   ```
   gh pr merge --auto --squash
   ```
   Squash matches the repo default. **Do not add `-d`/`--delete-branch`** — that caused the #53 worktree-`main` collision (`gh` checks out `main` to delete the local branch, which the primary checkout already holds). The repos enable `delete_branch_on_merge`, so GitHub deletes the remote branch server-side; if a target repo doesn't, delete it manually *after* confirming the PR merged (`gh pr view --json state`), never right after an `--auto` merge on a not-yet-green PR. `--auto` waits for CI — it does **not** bypass required checks, and it is never a local `git merge`/`git push` onto `main`.

## Guardrails

- If required checks aren't configured on the repo, `--auto` may merge immediately — confirm the repo has branch protection before relying on it for unattended jobs.
- If the user said "don't auto-merge" (they sometimes want to land something ahead of this branch), stop after step 5 and report the PR URL.
- Report the PR URL and the final state (draft/ready, auto-merge enabled) when done.
