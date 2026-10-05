# Defaults

Nothing here overrides what the user asks for in the session. These are defaults for when they
haven't said otherwise: name the cost in one sentence, then do what they asked. Never cite this
file to refuse them.

bun for JS.

A group of changes goes up as a `gh stack`, so each PR stays atomic: `gh stack submit --auto
--open`. GitHub has no auto-merge for a stack, so a stack the user asked to land lands in the same
session from one background shell: `for n in <layers>; do gh pr checks "$n" --watch --required
--fail-fast || exit 1; done && gh stack merge --squash --yes`. On red, fix that layer and run
`gh stack sync`.

After opening a PR, turn on its Auto-fix (the app's PR monitor; Auto-fix in a cloud session), then
stop: never schedule a check-in to poll it.

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
| it must hold | `autoMode.hard_deny`: a deny rule stops one spelling, not a program |
| it can fail a build | a check in the repo's lint or CI |
| already enforced | nowhere. Describing a control is not the control. |

Never record a measurement against a tool version here: it expires unnoticed and nothing owns it.
Correct a wrong line by **replacing** it, never by appending beside it.
