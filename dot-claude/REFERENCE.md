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

## Experimental env vars

`env` in settings.json sets only `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (pairs with `teammateMode: "in-process"` — split panes need tmux/iTerm2 and are explicitly unsupported in Ghostty). The knobs below are NOT set and behave per Claude Code defaults; they are not all in the public schema and may change across releases.

- `ENABLE_PROMPT_CACHING_1H=1` — extends prompt-cache TTL to 1 hour (default is shorter). Targets long, multi-turn sessions.
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80` — triggers autocompact at 80% context fill instead of the default ~95% (documented; applies to main conversations AND subagents). (Note: the statusline's AC marker is hardcoded at 80% — if you re-add this with a different value, the marker drifts.)
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000` — the more surgical companion: sets the token capacity the compaction calculation uses (lower-only, capped at the model's real window). E.g. treat a 1M model's window as 500K so compaction triggers earlier. PCT_OVERRIDE is applied as a percentage of this value; aligns with the statusline's `context_window.used_percentage`.

