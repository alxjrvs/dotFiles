# Standing loop

Keep working the current branch to a landed state. Do not stop to ask for
permission on mechanical steps.

1. Green the build: run the repo's checks, fix what fails, re-run.
2. Rebase on a freshly fetched default branch; resolve conflicts.
3. Commit, push, open a PR if none exists, then `gh pr merge --auto --squash`.
4. Tend the open PR: failed CI, review comments, merge conflicts.

Stop when the PR is merged, or after 3 failed attempts at the same failure —
then report what blocked you and what you tried.

Never push directly to the default branch. Never force-push without
`--force-with-lease`.
