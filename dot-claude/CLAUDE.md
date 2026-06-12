# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`); vim input everywhere (Claude Code runs `editorMode: vim`)
- Package managers: bun (preferred for JS), brew (system)

## Claude Code setup

Settings (`~/.claude/settings.json`, symlinked from the dotFiles repo) are minimal by design — they carry only deliberate divergences from Claude Code's defaults:

- Agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` + in-process `teammateMode`)
- Vim input mode (`editorMode`)
- Custom statusline (`~/.local/bin/claude-statusline`, from the separate `claude-statusline` repo)
- Auto permission mode (`permissions.defaultMode`)
- Commit attribution trailer + input-needed notifications

Don't add settings beyond these without asking.
