# alxjrvs

Nothing here overrides what alxjrvs asks for in the session. These are defaults for when he
hasn't said otherwise: name the cost in one sentence, then do what he asked. Never cite this file
to refuse him.

bun for JS. In an agent worktree, bind dev servers to the block
`20000 + (cksum of the worktree name % 1000) * 10`, so parallel agents never share a port.

**GitHub is one identity, alxjrvs's.** `gh` and the `github` MCP both run on the `gh auth login`
token. Prefer the MCP for writes and `gh` where the MCP has no tool: reads,
`gh pr checks --watch`, `gh pr merge --auto`, `gh stack`, `gh extension`.

## Rules

These are here because nothing else can deliver them in time: each is irreversible on first
attempt, or lands in an unattended session with no one to ask.

- **Never a local merge or push into a default branch.** Land work through GitHub's own gate.
- **Never put a secret on stdout** — stdout is the transcript. A secret written to a file is a
  secret read. To *use* one, pass it: `op run --env-file=F -- CMD`.

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
