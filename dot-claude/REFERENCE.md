# Claude Code Reference Cheatsheets

Personal notes that aren't instructions. Not auto-loaded — only `CLAUDE.md`, `settings.json`, `agents/`, and `commands/` are symlinked into `~/.claude/`. Read this on demand.

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
