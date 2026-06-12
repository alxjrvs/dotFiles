# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`); vim input everywhere (Claude Code runs `editorMode: vim`)
- Package managers: bun (preferred for JS), brew (system)

## Claude Code setup

Settings (`~/.claude/settings.json`, symlinked from the dotFiles repo) are minimal by design and carry exactly three things:

- Agent teams enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, in-process teammates)
- Vim input mode
- Custom statusline (`dot statusline` / `dot subagent-statusline`)

Don't add settings beyond these without asking.
