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
- When dispatching an `Agent` that will edit code, pass `isolation: "worktree"` — the worktree auto-cleans if no changes, and leaves a reviewable branch if there are edits.

## Skill Usage

Invoke skills before defaulting to ad-hoc behavior — they override the default system prompt where they conflict.

**Prefer `implement:*` (CDD cycle: Define → Generate → Verify) for code-change workflows.** Fall back to `superpowers:*` for anything implement doesn't cover.

Implement (first choice for code work):

- `implement:build` — orchestrates Define → Generate → Verify for any code change; scales from one-liner to full epic.
- `implement:define` — planning/breakdown only; dispatches Plan agents with distinct analytical perspectives.
- `implement:generate` — single TDD cycle (red-green-refactor, or verify mode for UI/config).
- `implement:verify` — code review gate after a changeset.
- `implement:adr` — record an architecture decision worth preserving.
- `implement:docgen` — generate / update project documentation.

Superpowers (fill-in for non-implementation work):

- `superpowers:brainstorming` — before any creative work when the task isn't yet well-defined.
- `superpowers:systematic-debugging` — on any bug, test failure, or unexpected behavior, before proposing a fix.
- `superpowers:verification-before-completion` — before claiming work done, fixed, or passing. Evidence before assertions.
- `superpowers:dispatching-parallel-agents` — for 2+ independent tasks with no shared state.
