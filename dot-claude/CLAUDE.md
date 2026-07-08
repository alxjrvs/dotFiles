# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`, vim keys); Claude Code matches via `editorMode: vim`
- Package managers: bun (preferred for JS), brew (system)

## Claude Code setup

`~/.claude/settings.json` (symlinked from the dotFiles repo) is minimal by design: only deliberate divergences from defaults, and the 1Password agent-secret architecture (service account, `op-agent` CLI, MCP secrets, git auth) that backs it. **Don't add settings beyond the documented divergences without asking.** For the full reference — what each divergence is and why, and how agent secret resolution works — see the `claude-agent-config` skill (loads on demand when touching `~/.claude/settings.json`, MCP wiring, or agent secrets).
