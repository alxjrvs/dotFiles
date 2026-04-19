# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`)
- Shell: zsh with vi keybindings
- Package managers: bun (preferred for JS), brew (system)
- Power user of Claude Code: hand-rolls dotfiles, hooks, statusline, ccusage integration. Assume familiarity with the feature surface. Don't soften recommendations or default to basic workflows — pitch the advanced option directly.

## Preferences

- Use bun over npm/yarn unless a project requires otherwise
- Use conventional commit style (feat:, fix:, chore:, etc.)
- When a term is ambiguous, ask for clarification rather than assuming a meaning
- No audio output from Claude or its hooks — no `say`, no notification sounds. Silent desktop notifications are fine. Voice input (me talking to Claude) is fine.
- **Meaningful-benefit filter**: for every proposed change, ask *does this provide real payoff?* Skip nice-to-haves, redundant additions, and belts-and-suspenders safety without a real risk. "Do them all" means "do the ones worth doing" — say what you're skipping and why. Completeness is not a virtue.

## Coding Style

- TypeScript by default for JS projects
- Prefer functional patterns over class-based
- Keep functions small and focused

## Git Workflow

- Default branch: main
- Rebase, squash, linear history. Avoid merge commits.
- `git push` and `git push --force-with-lease` are acceptable; NEVER run `git push --force`

## Tool Preferences

- For library/framework/SDK/API docs, prefer the `context7` MCP (`query-docs`) over `WebFetch`.
- For multi-file or multi-step work, enter plan mode (`EnterPlanMode`) before touching code. Short, clearly-scoped tasks don't need it.
- For long-running or polling work, use `ScheduleWakeup` or the `loop` skill rather than re-running commands manually.
- For codebase research spanning more than ~3 file lookups, dispatch the `Explore` subagent.
- When dispatching an `Agent` that edits code, pass `isolation: "worktree"`.
- When dispatching an `Agent`, default to `model: "sonnet"`. Use `"haiku"` for pure lookups (file reads, greps, one-shot searches). Reserve the default (opus) for architecture, debugging, code review, or tasks that explicitly need heavy reasoning.

## Skill Usage

Prefer `implement:*` (CDD cycle) for code changes; `superpowers:*` as fallback. Always run `superpowers:verification-before-completion` before claiming work done.
