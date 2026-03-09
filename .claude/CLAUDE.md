# dotFiles

Personal dotfiles managed with symlinks via `install.sh`.

## Structure

- `install.sh` — idempotent installer: brew, asdf, symlinks, macOS defaults
- `dot-claude/` — user-level Claude Code config, symlinked to `~/.claude/`
  - `CLAUDE.md` — global Claude instructions (applies to all projects)
  - `settings.json` — Claude Code settings (plugins, hooks, permissions)
  - `skills/` — shared skills
  - `agents/` — custom agents
- `.claude/` — repo-level Claude config (this repo only, not symlinked)

## Conventions

- Shell aliases and config go in `.zshrc`
- Git config goes in `.gitconfig`
- New tools/packages go in `Brewfile`
- Language versions go in `.tool-versions`
- All symlinks use the `link()` helper in `install.sh` (idempotent, with conflict resolution)

## Adding a new dotfile

1. Add the file to this repo
2. Add a `link` line in the `Symlinks` section of `install.sh`
3. Run `./install.sh` to verify
