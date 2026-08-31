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

---

## 2026-08-28 — the PR reviewer is gone, both halves

`dot-claude/hooks/pr-review.sh` (244 lines), `pr-review-settings.json`, its three PostToolUse
handlers, and `.github/workflows/claude-review.yml` are all deleted. Not narrowed — deleted.

### The finding that forced it

`pr-review.sh:26` stated its scope as *"opt-in per repo via `PR_REVIEW_REPOS` (a space-separated
allowlist)."* `PR_REVIEW_REPOS` was set **nowhere** — not in `zsh/`, not in `settings.json`, not in
the boomfile. So `:72`'s `: "${PR_REVIEW_REPOS:=$(_owned_orgs …)}"` defaulted it to every owned
org, and every `gh pr create`, `git push` and `gh stack submit` across six organizations fired a
background review that posted a comment.

The documented scope and the actual scope disagreed, in the direction that matters: the header's
own security note concedes the input is *"attacker-controlled (any contributor to a
`PR_REVIEW_REPOS` repo)"*. A hook that reads untrusted text from six orgs' PRs, on a laptop that
holds a service-account token and a PAT, is not something to re-scope. `CLAUDE.md`'s rule is
"Describing a control is not the control" — an allowlist nothing sets is a description.

### Why the workflow went too

`claude-review.yml` was the other half of the same decision, and its own header framed it as an
either/or: *"add `pull_request` here and delete `hooks/pr-review.sh` … or delete this file and keep
the local hook."* It was never resolved, because resolving it needed a measurement (E2 — whether
subscription-token Action runs draw on the weekly interactive limits) that needed the file on
`main` first.

Both branches of that choice keep a reviewer. Neither was taken, and the reason is in the file's
own notes: the CI reviewer is not a like-for-like replacement either. It *"skips … pull requests it
judges not to need a review"*, so coverage becomes non-deterministic; and on a public repo it
cannot run on fork PRs at all, silently. Meanwhile the thing it was going to restore — a blocking
check — was already conceded dead: *"Even the managed Code Review product completes its check run
neutral by design."*

So the honest reading is that this capability had no shape anyone wanted. `/code-review` still
exists, on demand, scoped to what is asked for, with no allowlist to drift and no daemon reading
other people's PRs.

### What the removal touched

`settings.json` loses its entire `PostToolUse` block — those three handlers were its only
occupants. `settings-guardrails.sh` loses the wiring assertion, `identity-drift.sh` the owner-list
entry, `boomfile.toml` both link stanzas, and README's fork list the sentence naming it.

`_owned_orgs()` is the one that changes meaning rather than losing a line. It is now a single
security boundary with a single reader (`repo-scope-guard.sh`). It had two readers, and the second
one is how a list written to answer *"where may an agent WRITE?"* came to also answer *"whose PRs
do we read?"* — a question nobody asked it.

> **Archived 2026-08-31.** Same class as the entry above: a mechanism deleted whole. Nothing named
> here exists — `pr-review.sh`, its settings file, its three PostToolUse handlers and the review
> workflow are all gone. The only surviving trace is a comment in `guard-lib.sh` recording that
> `_owned_orgs()` briefly had a second consumer, which is why that function is shaped as it is.
