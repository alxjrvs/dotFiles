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

`env` in settings.json now sets `EDITOR`, `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`, and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (enabled 2026-06-10; pairs with `teammateMode: "in-process"` — split panes need tmux/iTerm2 and are explicitly unsupported in Ghostty). The knobs below are NOT set and behave per Claude Code defaults; they are not all in the public schema and may change across releases.

- `ENABLE_PROMPT_CACHING_1H=1` — extends prompt-cache TTL to 1 hour (default is shorter). Targets long, multi-turn sessions.
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80` — triggers autocompact at 80% context fill instead of the default ~95% (documented; applies to main conversations AND subagents). (Note: the statusline's AC marker is hardcoded at 80% — if you re-add this with a different value, the marker drifts.)
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000` — the more surgical companion: sets the token capacity the compaction calculation uses (lower-only, capped at the model's real window). E.g. treat a 1M model's window as 500K so compaction triggers earlier. PCT_OVERRIDE is applied as a percentage of this value; aligns with the statusline's `context_window.used_percentage`.

## Hook events deliberately NOT wired

- `WorktreeCreate`/`WorktreeRemove` — these are creation DELEGATES, not
  post-create setup hooks: a WorktreeCreate hook must print the new worktree
  path to stdout, and ANY non-zero exit (or missing path) aborts worktree
  creation. They exist so EnterWorktree works outside git repos
  (VCS-agnostic isolation). Wiring them in this git-native setup risks
  breaking `EnterWorktree`/worktree flows for zero gain. Revisit only with a
  tested hook that re-implements git worktree creation end-to-end.
- Blocking `ConfigChange` — the wired `config-change` hook is telemetry-only
  (appends to `~/.claude/state/config-changes.jsonl`). A blocking variant
  (exit 2) would fire on every legitimate in-session settings.json edit —
  self-lock territory, same class as the Edit()-deny-on-live-settings trap.

## Sandbox gotchas (symptoms that look like config bugs but aren't)

These are runtime behaviors observed under the seatbelt sandbox that waste time if you assume the settings.json profile is wrong. It isn't — these are macOS/OS-level effects the sandbox config can't change.

- **`com.apple.provenance` xattr → "Operation not permitted" on `rm`/shell-redirect, even inside an allowed write root.** macOS tags files created by *other* apps (VS Code, Finder, downloads) with a `com.apple.provenance` extended attribute under its app-data protection / TCC. A sandboxed Bash `rm <file>` or `: > <file>` then fails with "Operation not permitted" *even when the path is inside an `allowWrite` root* — this is TCC, not seatbelt, so no `sandbox.filesystem` tweak fixes it. Seen on `SU-SRD packages/salvageunion-reference/.vscode/settings.json` and `~/Code/SU-SRD/.gnar-term/*`.
  - **Tell:** the Claude **Write** tool succeeds on the same path (it bypasses the sandbox), while Bash `rm`/redirect does not. That asymmetry is the fingerprint.
  - **Workaround:** delete/overwrite from a plain Terminal or Finder (outside the sandbox), or overwrite-in-place via the Write tool. Don't burn time hunting for a missing `allowWrite` entry — there isn't one to add.

- **Broad `**/.env.*` denyRead also catches `.env.example`/`.template`/`.sample`.** These non-secret templates are carved back in via `sandbox.filesystem.allowRead` (`/**/.env.example` etc.), which Claude compiles into the profile's `read.allowWithinDeny`. If a sandboxed `git status` over a repo that *tracks* `apps/*/.env.example` reports "Operation not permitted", confirm those allowRead carve-outs are still present (pinned by `tests/bats/hardening.bats`) before assuming a deeper sandbox fault — and rule out the provenance-xattr case above, which presents identically.
