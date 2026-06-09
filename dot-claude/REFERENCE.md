# Claude Code Reference Cheatsheets

Personal notes that aren't instructions. Not auto-loaded — only `CLAUDE.md` and `settings.json` are symlinked into `~/.claude/`. Read this on demand.

## Built-in slash commands worth remembering

The CC built-in surface is wider than I tend to use. Verified on v2.1.153+:

- `/rewind` (aliases `/checkpoint`, `/undo`) — restore code, conversation, or both to an earlier checkpoint. Cheaper than re-prompting when something goes sideways.
- `/btw <question>` — side question that does NOT enter conversation history. Use mid-feature when a one-off lookup would otherwise pollute context.
- `/branch [name]` (alias `/fork`) — fork the session to try risky work; return to trunk if it doesn't pan out.
- `/focus` — toggles hiding of intermediate tool calls (fullscreen TUI only). Pairs with auto mode + `/goal` for hands-off runs.
- `/goal <verifiable-condition>` — iterate until a deterministic check passes (e.g. "all tests in test/auth pass and lint is clean"). Distinct from `/loop`: condition-based, not interval-based. Cancel with `/goal clear`.
- `/insights` — usage-pattern report. Worth running periodically.
- `/copy [N]` — copy last response with code-block picker. `/copy 2` for second-to-last.
- `/context [all]` — visualize context fill. Check before deciding whether to `/compact` for the next feature.
- `/export [filename]` — dump conversation. With filename writes directly; without opens a clipboard/file dialog.

For non-interactive `claude -p` invocations from scripts, pass `--bare` to skip hooks, skills, plugins, MCP, auto-memory, and CLAUDE.md — sets `CLAUDE_CODE_SIMPLE` and starts faster. Verify per-script whether the missing infrastructure matters before adopting.

## Experimental env vars (NOT currently set)

The lean settings.json baseline (2026-06 rebuild) sets only `EDITOR` and `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`. The knobs below were set before the rebuild and behave per Claude Code defaults now; re-add to `env` in settings.json if wanted. They are not in the public schema and may change or disappear across releases.

- `ENABLE_PROMPT_CACHING_1H=1` — extends prompt-cache TTL to 1 hour (default is shorter). Targets long, multi-turn sessions.
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80` — triggers autocompact at 80% context fill instead of the default. (Note: the statusline's AC marker is hardcoded at 80% — if you re-add this with a different value, the marker drifts.)
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` — enables multi-agent team dispatch (`Agent` tool `team_name`/`name` params); without it those calls degrade to single-agent dispatch.
