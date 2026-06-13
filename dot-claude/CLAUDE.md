# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`, vim keys); Claude Code uses its default `normal` input mode (no `editorMode` override)
- Package managers: bun (preferred for JS), brew (system)

## Claude Code setup

Settings (`~/.claude/settings.json`, symlinked from the dotFiles repo) are minimal by design — they carry only deliberate divergences from Claude Code's defaults:

- Agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` + in-process `teammateMode`)
- Agents view disabled (`disableAgentView: true`) — turns off the `claude agents` view / `--bg` / `/background` on-demand dispatch. Independent of Agent teams above (teams stay on; only the view is off).
- Quieter UI (`showTurnDuration: false`, `terminalProgressBarEnabled: false`) — no per-turn duration line, no terminal progress bar
- Custom statusline (`~/.local/bin/claude-statusline`, from the separate `claude-statusline` repo)
- Auto permission mode (`permissions.defaultMode`) — a deliberate productivity tradeoff: it auto-approves tool calls, removing the per-call human gate. Accepted risk, but **re-evaluate periodically** — it removes the safety net against prompt injection / confused-deputy scenarios, and the user-scope GitHub MCP server widens that surface across all projects. Scope down via a project-level `settings.local.json` for any repo that warrants it.
- Commit attribution trailer + input-needed notifications
- Claude's commit identity (`env` `GIT_AUTHOR_*`/`GIT_COMMITTER_*` → `Claude <alxjrvs+claude@gmail.com>`, `GIT_CONFIG_*` → `commit.gpgsign=false`): commits Claude makes are authored under a distinct, unsigned identity so they never need a 1Password unlock, while your own terminal git (and `gh`) keep `alxjrvs` + 1Password signing. The `attribution.commit` trailer credits you as co-author. Add `alxjrvs+claude@gmail.com` on GitHub to link these commits to your profile.

Don't add settings beyond these without asking.
