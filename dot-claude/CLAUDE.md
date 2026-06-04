# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: helix (`hx`)
- Shell: zsh with vi keybindings
- Package managers: bun (preferred for JS), brew (system)
- Power user of Claude Code: hand-rolls dotfiles, hooks, statusline. Assume familiarity with the feature surface.

## Preferences

- Use bun over npm/yarn unless a project requires otherwise
- Use conventional commit style (feat:, fix:, chore:, etc.)
- **Secrets handling**: 1Password CLI (`op`) is the source of truth. NEVER propose adding a plaintext token to `.env`, `.npmrc`, or any config file. Default to an `op://` reference + the `op-run` wrapper, or `direnv` + `op read` in a per-project `.envrc` for fork-time inheritance. The only exception is keychain-backed CLIs (e.g., the `gh auth token` fallback handles GitHub) — document inline why the standard patterns don't apply. If you find an existing plaintext token in any repo, flag it before doing anything else: revoke first, then migrate.

## Git Workflow

- Default branch `main`; rebase, squash, linear history.
- Hard rules (`--no-verify`, `--no-gpg-sign`, `git push --force` without `--force-with-lease`, force branch deletion) are blocked by `dot hook policy-guard` + `permissions.deny` in `dot-claude/settings.json` — don't try to work around them.
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

Prefer `implement:*` (CDD cycle) for code changes; `superpowers:*` as fallback. Always run `superpowers:verification-before-completion` before claiming work done.

## Built-in slash commands worth remembering

The CC built-in surface is wider than I tend to use. Verified on v2.1.153+:

- `/rewind` (aliases `/checkpoint`, `/undo`) — restore code, conversation, or both to an earlier checkpoint. Cheaper than re-prompting when something goes sideways.
- `/btw <question>` — side question that does NOT enter conversation history. Use mid-feature when a one-off lookup would otherwise pollute context.
- `/branch [name]` (alias `/fork`) — fork the session to try risky work; return to trunk if it doesn't pan out.
- `/focus` — toggles hiding of intermediate tool calls (fullscreen TUI only — `"tui": "fullscreen"` is set). Pairs with auto mode + `/goal` for hands-off runs.
- `/goal <verifiable-condition>` — iterate until a deterministic check passes (e.g. "all tests in test/auth pass and lint is clean"). Distinct from `/loop`: condition-based, not interval-based. Cancel with `/goal clear`.
- `/insights` — usage-pattern report. Run alongside `meta:tuneup` periodically.
- `/copy [N]` — copy last response with code-block picker. `/copy 2` for second-to-last.
- `/context [all]` — visualize context fill. Check before deciding whether to `/compact` for the next feature.
- `/export [filename]` — dump conversation. With filename writes directly; without opens a clipboard/file dialog.

For non-interactive `claude -p` invocations from scripts, pass `--bare` to skip hooks, skills, plugins, MCP, auto-memory, and CLAUDE.md — sets `CLAUDE_CODE_SIMPLE` and starts faster. Verify per-script whether the missing infrastructure matters before adopting.

## Experimental env vars in settings.json

These are not in the public schema and may change or disappear across Claude Code releases. Test after upgrades. If one is removed upstream, settings.json continues to parse but the behavior reverts to default.

- `ENABLE_PROMPT_CACHING_1H=1` — extends prompt-cache TTL to 1 hour (default is shorter). Targets long, multi-turn sessions; if removed, cache hits drop and per-turn token cost rises.
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80` — triggers autocompact at 80% context fill instead of the default. Lower threshold = earlier compaction = less mid-feature truncation; if removed, autocompact fires later and is more likely to interrupt feature boundaries.
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` — enables multi-agent team dispatch. Used by the `Agent` tool's `team_name`/`name` params; if removed, those calls degrade to single-agent dispatch.
