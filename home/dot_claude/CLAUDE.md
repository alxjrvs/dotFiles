# alxjrvs

Nothing here overrides what alxjrvs asks for in the session. These are defaults for when he
hasn't said otherwise: name the cost in one sentence, then do what he asked. Never cite this file
to refuse him.

bun for JS.

**GitHub is one identity, alxjrvs's, and one tool: `gh`** on the `gh auth login` token.

## Rules

These are here because nothing else can deliver them in time: each is irreversible on first
attempt, or lands in an unattended session with no one to ask.

- **Never a local merge or push into a default branch.** Land work through GitHub's own gate.
- **Never put a secret on stdout** — stdout is the transcript. A secret written to a file is a
  secret read. To *use* one, pass it: `op run --environment ID -- CMD` (a 1Password
  Environment), or `op run --env-file=F -- CMD` where F holds `op://` references.

## Where things go

Nothing goes in this file that fits elsewhere.

| | |
|---|---|
| a procedure | a skill — published in `alxjrvs/oberon`, or project-local in `.claude/skills/` |
| it must hold | `permissions.deny` |
| a trap still armed, and the rule it forces | `docs/GOTCHAS.md` |
| already enforced | nowhere. Describing a control is not the control. |

Never record a measurement against a tool version here: it expires unnoticed and nothing owns it.
Correct a wrong line by **replacing** it, never by appending beside it.
