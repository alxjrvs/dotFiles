---
name: worktree-triage
description: Diagnose why a Claude Code agent worktree will not close - "has commits that are not pushed anywhere", a dirty tree, a stacked branch, or a lock held by a live session - and give the one command that clears each. Use when a session refuses to delete, or when sweeping stale worktrees.
---

# worktree-triage

Why a worktree will not close, and the single command that clears each case.
This lived only in a hook header, which meant it was re-derived every time it
came up.

## Read the refusal first — there are only two, and they behave differently

Claude Code's delete path clears a worktree only if

```
git rev-list --max-count=1 HEAD --not --remotes      # empty
```

or the branch's upstream reads exactly `gone` AND every commit patch-id matches
`origin/<default>`.

**`kept — dirty`** is waivable. `force` appears on that arm.

**`kept — has commits that are not pushed anywhere`** is NOT. `force` does not
appear on that arm, and there is no setting, keystroke or discard path for it.
The condition can only be falsified — you make the commits exist somewhere — never
waived. Do not go looking for a flag; there isn't one.

An agent worktree is cut `--no-track`, so it has no upstream at all. Its
`%(upstream:track)` is empty rather than the literal `gone` the content-based
escape requires, which is why **a squash-merged branch stays blocked even though
its content already landed**. That is the case that looks like a bug and isn't.

## Triage

Run from the worktree, or with `-C <path>`:

```sh
git status --porcelain                      # dirty?
git rev-list --max-count=1 HEAD --not --remotes   # empty = closeable
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null
git log --oneline origin/main..HEAD
cat "$(git rev-parse --git-common-dir)/worktrees/<name>/locked" 2>/dev/null
```

| what you see | what it is | the one command |
|---|---|---|
| `rev-list` empty | already closeable | close it; nothing to do |
| Commits, no upstream, work is real | never published | `git push -u origin HEAD` |
| Commits, but content is on main | squash-merged; the patch-ids match and the escape still cannot fire | `boom code reap` — it re-decides by `git patch-id` and removes what actually landed |
| Dirty tree | waivable | commit it, or discard and force |
| Part of a `gh stack` | do NOT push it bare; that retargets nothing | `gh stack submit` |
| `locked` names a LIVE pid | another session is working in it | wait, or close that session. `worktree-remove-guard.sh` refuses this |
| `locked` names a dead pid | abandoned | safe to remove |

Check liveness with `kill -0 <pid>` — but note a process owned by another user
returns EPERM and reads as dead. Every Claude session here runs as the same user,
so it does not arise in practice.

## The sweep

`boom code reap` runs daily, and since 2026-08-28 it is the ONLY mechanism.
There was a `worktree-publish.sh` hook that published a branch the moment its
agent went idle; it is gone, along with the `--push` half of this sweep, which had
recorded 0 successful pushes against 84 failures over 14 runs. So a refusal you
hit by hand is now expected rather than a hook that failed to fire — nothing
publishes for you. Push it yourself, or leave it for the sweep to reap once its
content lands on the default branch.

`reap` is safer than the client's own check: it re-decides by content, reads
`gh stack` topology, and removes only clean, unlocked, already-merged-or-pushed
worktrees, always leaving the branch ref. It cannot lose a commit.

## The gap worth knowing

Subagent worktrees (`isolation: worktree`) get no port block: `worktree-port.sh`
is deliberately not wired on SubagentStart/SubagentStop because those events carry
the PARENT's cwd, not the subagent's. Nothing publishes them either — but that is
now true of every worktree, not a subagent-specific gap. A finished subagent
worktree falls through to the daily reap, up to 24h where it cannot be closed by
hand. If you hit that, publish it directly:
`git -C <worktree> push -u origin HEAD`.
