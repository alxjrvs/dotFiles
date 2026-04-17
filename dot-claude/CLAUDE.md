# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`)
- Shell: zsh with vi keybindings
- Package managers: bun (preferred for JS), brew (system)

## Preferences

- Use bun over npm/yarn unless a project requires otherwise
- Use conventional commit style (feat:, fix:, chore:, etc.)
- Prefer editing existing files over creating new ones
- No emojis in code or commit messages unless asked
- Make only the changes requested. Do not add autonomous fixes, refactors, or improvements the user didn't ask for
- When a term is ambiguous, ask for clarification rather than assuming a meaning

## Coding Style

- TypeScript by default for JS projects
- Prefer functional patterns over class-based
- Keep functions small and focused
- Avoid over-engineering; solve the problem at hand

## Git Workflow

- Default branch: main
- Rebase on pull (`pull.rebase = true`)
- Push auto-sets upstream (`push.autoSetupRemote = true`)
- Rerere enabled for conflict resolution
- `git push` and `git push --force-with-lease` are acceptable; NEVER run `git push --force`

## Tool Preferences

- For library, framework, SDK, or API docs, prefer the `context7` MCP (`query-docs`) over `WebFetch`. Faster, more accurate, and doesn't consume browse budget.
- For multi-file or multi-step work, enter plan mode (`EnterPlanMode`) before touching code. Short, clearly-scoped tasks (one or two files) don't need it.
- For long-running or polling work (CI checks, deploy status, slow builds), use `ScheduleWakeup` or the `loop` skill rather than manually re-running commands.
- For codebase research spanning more than ~3 file lookups, dispatch the `Explore` subagent rather than grepping inline.

## Skill Usage

Invoke these before defaulting to ad-hoc behavior — they override the default system prompt where they conflict:

- `superpowers:brainstorming` — before any creative work: features, components, behavior changes.
- `superpowers:systematic-debugging` — on any bug, test failure, or unexpected behavior, before proposing a fix.
- `superpowers:writing-plans` / `superpowers:executing-plans` — for multi-step implementations; writes the plan, then executes it with review checkpoints.
- `superpowers:test-driven-development` — when implementing a feature or bugfix with testable logic.
- `superpowers:verification-before-completion` — before claiming work done, fixed, or passing. Evidence before assertions.
- `superpowers:requesting-code-review` — before merging or at major milestones.
