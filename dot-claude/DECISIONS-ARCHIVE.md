# Claude Config — Decisions Archive

Entries whose mechanism no longer exists. Moved here under `DECISIONS.md`'s retention
rule 3 ("archive by subject, not by age"), which this file is the first exercise of.

Nothing here is deleted and nothing here is edited into agreement with the present —
these are the entries whose subject is gone, moved out of the live log so it stays
answerable rather than encyclopaedic. Age is not the criterion: the oldest entry in
`DECISIONS.md` is still the reason a live guard is shaped the way it is.

---

## 2026-08-28 — the publish-at-idle design is gone, and its log says why

`dot-claude/hooks/worktree-publish.sh` (168 lines), `tests/publish.sh` (293), the `Stop` and
`SessionEnd` wiring, both boomfile link stanzas, and the `--push` flag on the daily `code reap`
timer are all removed.

### The measurement

```
~/.local/state/boom/logs/com.boomtube.code-reap---push.log
  grep -c 'CODE REAP'   → 14
  grep -c 'pushed'      → 0
  grep -c 'push failed' → 84
```

**Zero successful pushes in fourteen sweeps.** The cause is mundane — `.gitconfig` resolves GitHub
auth through `gh auth git-credential`, and a launchd job runs outside any session where that works
— but it went unnoticed for weeks, because the finding died in a log nothing reads. The timer was
carrying the entire outward blast radius of the design (those branches land on origin, including
org repos) for a benefit it had never once delivered.

That is a cleaner argument than any reasoning about the design: the `--push` half could be deleted
with **no** behavioural change, because it was already not happening.

### The hook is a separate argument, and it is honest to say so

`worktree-publish.sh` ran in-session, where `gh auth` works, so it plausibly *was* publishing. The
0/84 does not indict it. What indicts it is what it is: a synchronous, outward-facing `git push`
to any of six organizations, fired at the end of every agent turn, before the user sees the reply.

Its purpose was real — Claude Code refuses to remove a worktree holding commits on no remote, and
`force` bypasses only the `dirty` arm, so the condition can be falsified but never waived. The
question is what falsifying it is worth. Measured against the reap log's own numbers, the sweeps
found 4–16 stuck worktrees each; the cost of the refusal is typing `git push` before closing a
session, on the order of thirty seconds, a few times a week.

Half a minute of friction is not worth a daemon authorized to write to other people's
repositories. `boom code reap` still runs daily and still falsifies the same condition the correct
way — by content, with `git patch-id` — and one sweep reaped 33 worktrees, so the mechanism that
works is the one that stayed.

### What is now un-handled, stated plainly

A clean worktree whose commits exist nowhere but this machine stays un-closeable until someone
pushes it. There is no automation left for that case, deliberately.

The canary keeps watching the `has commits that are not pushed anywhere` literal. It is still
load-bearing: `code reap` exists to falsify exactly that refusal, so the day the client stops
emitting the string is the day the reap timer can go too.

> **Archived 2026-08-31.** `boom code` was removed from boom's surface, taking `code
> reap` and `code fetch` with it. This entry's closing prediction — "the day the client
> stops emitting the string is the day the reap timer can go too" — was answered the
> other way round: the timer went first, so the canary fingerprint that watched that
> literal was removed rather than kept waiting. Nothing described above still exists.
