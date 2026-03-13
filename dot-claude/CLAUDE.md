# User-Level Claude Code Instructions

## Identity

- Name: alxjrvs
- Editor: neovim (`nvim`)
- Shell: zsh with vi keybindings
- Package managers: bun (preferred for JS), brew (system)

## Preferences

- Keep responses concise and direct
- Use bun over npm/yarn unless a project requires otherwise
- Never auto-commit; always ask first
- Use conventional commit style (feat:, fix:, chore:, etc.)
- Prefer editing existing files over creating new ones
- No emojis in code or commit messages unless asked

## Coding Style

- TypeScript by default for JS projects
- Prefer functional patterns over class-based
- Keep functions small and focused
- Avoid over-engineering; solve the problem at hand

## Git Workflow

- Default branch: main
- Rebase on pull (`pull.rebase = true`)
- Push auto-sets upstream (`push.autoSetupRemote = true`)
- Rerere enabled for conflict resolution
- NEVER run `git push --force` under any circumstances

## Dotfiles

- Managed at `~/dotFiles` with symlinks via `sync.sh` (alias: `env-sync`)
- Changes to shell config go in `.zshrc`
- Changes to git config go in `.gitconfig`
- Claude settings live in `.claude/` and are symlinked to `~/.claude/`
