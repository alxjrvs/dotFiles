# dotFiles: what a bare `/loop` runs here

Run the standing loop in `~/.claude/loop.md` with the facts that are this
repo's own. It is named rather than copied, so there is one loop to keep right.

1. Prove a change with `mise run lint apply-check` before opening the PR.
   `apply-check` applies the source into a temporary home; never apply a
   worktree to the real one.
2. `main` takes squash-merged pull requests with `lint` green and no bypass, so
   the completion path is `gh pr merge --auto --squash`. Never push to `main`,
   and never merge into it locally.
3. A PR that touches `home/dot_claude/` or `home/.chezmoiscripts/` changes what
   agents may do or what runs on the next apply. Stop at green and leave it
   open for alxjrvs to merge: no `--auto`.
