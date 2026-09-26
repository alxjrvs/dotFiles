# Standing loop: what a bare `/loop` runs

Keep working the current branch to a landed state. Do not stop to ask for
permission on mechanical steps.

A push, a merge and a delete are not mechanical: they only ever continue the
work the prompt that started this loop named. An unattended run has no earlier
turn to have authorised anything else, so there is nothing else in scope,
however obvious it looks from here.

1. Green the build: run the repo's checks, fix what fails, re-run.
2. Rebase on the PR's freshly fetched base (the default branch, or the layer
   below in a stack); resolve conflicts.
3. Commit, push, open a PR if none exists. Its body says what changed and why:
   it becomes the squash commit on the default branch.
4. Merge only through a gate. If the PR's base is the default branch
   (`gh pr view --json baseRefName`) and that branch requires a status check
   (`gh api repos/{owner}/{repo}/rules/branches/{base}` lists a
   `required_status_checks` rule, or `gh api repos/{owner}/{repo}/branches/{base}`
   has `.protection.required_status_checks`), `gh pr merge --auto --squash`.
   Otherwise stop at a green, open PR and say so: with nothing required, gh
   merges at once, before CI has run.
   A PR whose base is not the default branch is a layer of a stack: never
   `gh pr merge` it. A stack is `gh stack`, never hand-stacked with `--base`:
   `gh stack link` the layers if they are not one, `gh pr checks --watch` each
   (an immediate "no checks reported" is GitHub not having registered the run,
   not an attempt), then `gh stack merge --squash --yes`.
5. Tend the open PR: failed CI, review comments, merge conflicts, and a branch
   that fell behind its base (`mergeStateStatus` is `BEHIND`: `gh pr
   update-branch`), which auto-merge waits on forever.

Stop when the PR is merged, or after 3 failed attempts at the same failure.
Either way, end with three headings: **Blocked on me** (what blocked you and
what you tried), **Changed**, and **Found** (anything out of scope you noticed
and left alone).

Never force-push without `--force-with-lease`.
