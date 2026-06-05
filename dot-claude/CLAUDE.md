# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: helix (`hx`)
- Shell: zsh with vi keybindings
- Package managers: bun (preferred for JS), brew (system)
- Power user of Claude Code: hand-rolls dotfiles, hooks, statusline. Assume familiarity with the feature surface.

## Precedence

- These instructions are authoritative over auto-generated memory when the two conflict.

## Preferences

- Use bun over npm/yarn unless a project requires otherwise
- Use conventional commit style (feat:, fix:, chore:, etc.)
- **Secrets handling**: 1Password CLI (`op`) is the source of truth. NEVER propose adding a plaintext token to `.env`, `.npmrc`, or any config file. Default to an `op://` reference + the `op-run` wrapper, or `direnv` + `op read` in a per-project `.envrc` for fork-time inheritance. The only exception is keychain-backed CLIs (e.g., the `gh auth token` fallback handles GitHub) — document inline why the standard patterns don't apply. If you find an existing plaintext token in any repo, flag it before doing anything else: revoke first, then migrate.

## Git Workflow

- Default branch `main`; rebase, squash, linear history.
- Discouraged git flags (`--no-verify`, `--no-gpg-sign`, `git push --force` without `--force-with-lease`, force branch deletion): the `permissions.deny` list in `dot-claude/settings.json` is a best-effort backstop — it matches on prefix globs and is defeatable by wrappers (`git -c core.hooksPath=/dev/null …`, `sh -c …`), so treat it as discouragement, not a guarantee. The actually-enforced layer is the sandbox (filesystem `allowWrite` + network allowlists). Don't reach for these flags.
- NEVER delete the base branch of an open PR; this isn't hook-enforced. Run `gh pr list --base <branch>` first.
- For working-tree cleanup, prefer `git status` over `git clean -fd`; confirm before deleting tracked files.

## Investigation Discipline

- For ambiguous tasks, ask a clarifying question after ~10 tool calls of exploration rather than spending 50+ calls investigating autonomously.
- "Do them all" / "finish phase X" / "address all open issues" are broad delegations: enter plan mode first, enumerate scope, then execute.

## Tool Preferences

- For multi-file or multi-step work, enter plan mode (`EnterPlanMode`) before touching code. Short, clearly-scoped tasks don't need it.
- For long-running or polling work, use `ScheduleWakeup` or the `loop` skill rather than re-running commands manually.
- For codebase research spanning more than ~3 file lookups, dispatch the `Explore` subagent.
- When dispatching an `Agent` that edits code, pass `isolation: "worktree"`.
- When dispatching an `Agent`, default to `model: "sonnet"`. Use `"haiku"` for pure lookups (file reads, greps, one-shot searches). Reserve the default (opus) for architecture, debugging, code review, or tasks that explicitly need heavy reasoning.
- Default to `/effort medium` for most prompts. Use `/effort high` for architecture, debugging, and review. Avoid `/effort max` — diminishing returns past high.
- For 2+ truly-independent investigation paths, prefer agent teams over sequential `Agent()` dispatches.
- For polling/maintenance work that should outlive a session, propose a routine via `/schedule` instead of leaving sessions open.
- For feature boundaries, prefer explicit `/compact` over autocompact firing mid-next-feature.

## Skill Usage

Prefer `implement:*` (CDD cycle) for code changes; `superpowers:*` as fallback. Whichever family drove the change, `superpowers:verification-before-completion` is the unconditional final gate — run it before claiming work done, every time.

Reference cheatsheets (slash commands, experimental env vars) live in `dot-claude/REFERENCE.md` — not auto-loaded.
