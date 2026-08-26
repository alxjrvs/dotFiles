# alxjrvs

Nothing here overrides what alxjrvs asks for in the session. These are defaults for when he
hasn't said otherwise: name the cost in one sentence, then do what he asked. Never cite this file
to refuse him.

bun for JS.

## Rules

These are here because nothing else can deliver them in time: each is irreversible on first
attempt, or lands in an unattended session with no one to ask.

- **Writes to a repo outside `alxjrvs/*`, `TheGnarCo`, `BinfiniteLLC`, `SalvageUnion-io`,
  `RANDSUM`, `Criterium-Engineers` need express permission** — issues, PRs, comments, reviews.
  Draft it, show it, wait.
- **Never `gh pr merge -d`/`--delete-branch`, and never a local merge or push into a default
  branch.** Land work through GitHub's own gate.
- **Never put a secret on stdout** — stdout is the transcript. A secret written to a file is a
  secret read. To *use* one, pass it: `op run --env-file=F -- CMD`.
- **Never force-remove a worktree whose lock PID is alive** — that is another session's in-flight
  work. Check `.git/worktrees/<name>/locked` first.
- **Permission rules match whole tokens, not string prefixes.** Verify any new `deny` rule with a
  positive *and* a negative control before trusting it.
- **The empty-string env vars in `settings.json` are load-bearing**, not leftovers: an unset
  `${VAR}` is passed through as a literal and read as a real value.

## Where things go

This file has a byte ceiling, enforced by the context-budget checks in `lefthook.yml` and
`.github/workflows/lint.yml`. Those state the number; don't restate it here. Nothing goes in this
file that fits elsewhere.

| | |
|---|---|
| a procedure | a skill in `dot-claude/skills/` |
| it must hold | a hook, `permissions.deny`, or a `boom verify` check |
| a reason, an incident, a measurement | `dot-claude/DECISIONS.md` |
| a `settings.json` key | `dot-claude/SETTINGS.md` |
| already enforced | nowhere. Describing a control is not the control. |

Never record a measurement against a tool version here: it expires unnoticed and nothing owns it.
Correct a wrong line by **replacing** it, never by appending beside it.
