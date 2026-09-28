# Defaults

Nothing here overrides what the user asks for in the session. These are defaults for when they
haven't said otherwise: name the cost in one sentence, then do what they asked. Never cite this
file to refuse them.

bun for JS.

**GitHub is one identity, the user's, and one tool: `gh`** on the `gh auth login` token.

## Rules

These are here because nothing else can deliver them in time: each is irreversible on first
attempt, or lands in an unattended session with no one to ask.

- **Never put a secret on stdout** — stdout is the transcript. A secret written to a file is a
  secret read. To *use* one, pass it: `op run --env-file=F -- CMD`, where F holds `op://`
  references.

## Where things go

Nothing goes in this file that fits elsewhere.

| | |
|---|---|
| a procedure | a skill: user-wide in dotFiles' `home/dot_claude/skills/`, or project-local in `.claude/skills/` |
| it must hold | `permissions.deny`, or `autoMode.hard_deny` where no command pattern can say it |
| it can fail a build | a check in the repo's lint or CI |
| already enforced | nowhere. Describing a control is not the control. |

Never record a measurement against a tool version here: it expires unnoticed and nothing owns it.
Correct a wrong line by **replacing** it, never by appending beside it.
