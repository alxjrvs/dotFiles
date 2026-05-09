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
- NEVER use `--no-verify` on commit/push. Pre-commit and pre-push hooks are mandatory; if a hook fails, fix the underlying issue.
- NEVER delete the base branch of an open PR — it permanently closes dependent PRs. Run `gh pr list --base <branch>` before any branch deletion.
- Do not delete tracked files during working-tree cleanup without explicit confirmation. `git clean -fd` is destructive; prefer `git status` first.

## Investigation Discipline

- For ambiguous tasks, ask a clarifying question after ~10 tool calls of exploration rather than spending 50+ calls investigating autonomously.
- "Do them all" / "finish phase X" / "address all open issues" are broad delegations: enter plan mode first, enumerate scope, then execute.

## Tool Preferences

- For library/framework/SDK/API docs, prefer the `context7` MCP (`query-docs`) over `WebFetch`.
- For multi-file or multi-step work, enter plan mode (`EnterPlanMode`) before touching code. Short, clearly-scoped tasks don't need it.
- For long-running or polling work, use `ScheduleWakeup` or the `loop` skill rather than re-running commands manually.
- For codebase research spanning more than ~3 file lookups, dispatch the `Explore` subagent.
- When dispatching an `Agent` that edits code, pass `isolation: "worktree"`.
- When dispatching an `Agent`, default to `model: "sonnet"`. Use `"haiku"` for pure lookups (file reads, greps, one-shot searches). Reserve the default (opus) for architecture, debugging, code review, or tasks that explicitly need heavy reasoning.
- Default to `/effort medium` for most prompts. Use `/effort high` for architecture, debugging, and review. Avoid `/effort max` — diminishing returns past high.
- When the `mcp__gnar-term` MCP is available, lean on it as a first-class tool — use its full feature surface naturally (spawning windows/panes for worktrees and parallel work, sending input to other panes, querying terminal state, etc.). Don't fall back to less capable alternatives just out of habit.

## Worktrees

- Worktree directory: `.worktrees`

## Skill Usage

Prefer `implement:*` (CDD cycle) for code changes; `superpowers:*` as fallback. Always run `superpowers:verification-before-completion` before claiming work done.
